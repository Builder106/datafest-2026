# Resolve repo root portably (Rscript or source(); override via DATAFEST_ROOT)
ROOT <- local({
  e <- Sys.getenv("DATAFEST_ROOT")
  if (nzchar(e)) return(normalizePath(e, mustWork = FALSE))
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  self <- if (length(f)) gsub("~+~", " ", f[[1]], fixed = TRUE) else {
    p <- NULL
    for (i in rev(seq_len(sys.nframe()))) {
      o <- tryCatch(get("ofile", envir = sys.frame(i), inherits = FALSE),
                    error = function(e) NULL)
      if (!is.null(o)) { p <- o; break }
    }
    p
  }
  if (is.null(self)) normalizePath(getwd(), mustWork = FALSE)
  else normalizePath(file.path(dirname(self), "..", ".."), mustWork = FALSE)
})

source(file.path(ROOT, "analysis", "R", "00_config.R"))

log_note("03_journey: start")
con <- connect_db(read_only = FALSE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

TRANSPORT_Q <- c(
  "In the past 12 months, has lack of transportation kept you from medical appointments or from getting medications?",
  "In the past 12 months, has lack of transportation kept you from meetings, work, or from getting things needed for daily living?"
)

log_note("1) per-patient transportation status from sdoh answers")
dbExecute(con, "DROP TABLE IF EXISTS patient_transport;")
dbExecute(con, sprintf("
  CREATE TABLE patient_transport AS
  WITH transport AS (
    SELECT PatientDurableKey,
           AnswerText,
           COUNT(*) AS n
    FROM sdoh
    WHERE Domain = 'Transportation Needs'
      AND DisplayName IN ('%s','%s')
      AND PatientDurableKey IS NOT NULL
    GROUP BY PatientDurableKey, AnswerText
  )
  SELECT
    PatientDurableKey,
    MAX(CASE WHEN AnswerText = 'Yes' THEN 1 ELSE 0 END) AS transport_yes,
    MAX(CASE WHEN AnswerText = 'No'  THEN 1 ELSE 0 END) AS transport_no,
    MAX(CASE WHEN AnswerText IN ('Patient declined','Patient unable to answer') THEN 1 ELSE 0 END) AS transport_declined,
    SUM(CASE WHEN AnswerText = 'Yes' THEN n ELSE 0 END) AS n_yes,
    SUM(CASE WHEN AnswerText = 'No'  THEN n ELSE 0 END) AS n_no
  FROM transport
  GROUP BY PatientDurableKey;",
  gsub("'", "''", TRANSPORT_Q[1]), gsub("'", "''", TRANSPORT_Q[2])))

dbExecute(con, "
  ALTER TABLE patient_transport ADD COLUMN transport_status VARCHAR;")
dbExecute(con, "
  UPDATE patient_transport
  SET transport_status = CASE
    WHEN transport_yes = 1              THEN 'barrier'
    WHEN transport_no  = 1              THEN 'no_barrier'
    WHEN transport_declined = 1         THEN 'declined'
    ELSE 'other'
  END;")

tp_mix <- dbGetQuery(con, "
  SELECT transport_status, COUNT(*) n_patients,
         SUM(transport_yes) n_ever_yes, SUM(transport_no) n_ever_no
  FROM patient_transport GROUP BY transport_status ORDER BY n_patients DESC;")
print(tp_mix); save_tbl(tp_mix, "journey_transport_status_mix.csv")

log_note("2) patient-level encounter summary (all patients)")
dbExecute(con, "DROP TABLE IF EXISTS patient_journey;")
dbExecute(con, "
  CREATE TABLE patient_journey AS
  SELECT
    e.PatientDurableKey,
    COUNT(*)                                      AS n_encounters,
    MIN(e.encounter_ts)                           AS first_ts,
    MAX(e.encounter_ts)                           AS last_ts,
    DATE_DIFF('day', MIN(e.encounter_ts), MAX(e.encounter_ts)) AS days_observed,
    SUM(e.IsEdVisit)                              AS n_ed,
    SUM(e.IsInpatientAdmission)                   AS n_inpatient,
    SUM(e.IsHospitalAdmission)                    AS n_hospadm,
    SUM(e.IsObservation)                          AS n_obs,
    SUM(e.IsOutpatientFaceToFaceVisit)            AS n_opf2f,
    SUM(e.IsHospitalOutpatientVisit)              AS n_hod,
    COUNT(DISTINCT e.DepartmentKey)               AS n_departments,
    COUNT(DISTINCT e.ProviderDurableKey)          AS n_providers,
    COUNT(DISTINCT DATE_TRUNC('day', e.encounter_ts)) AS n_distinct_days
  FROM encounters e
  GROUP BY e.PatientDurableKey;")

log_note("3) gap-time distribution per patient (median days between consecutive encounters)")
dbExecute(con, "DROP TABLE IF EXISTS patient_gaps;")
dbExecute(con, "
  CREATE TABLE patient_gaps AS
  WITH ord AS (
    SELECT PatientDurableKey, encounter_ts,
           LEAD(encounter_ts) OVER (PARTITION BY PatientDurableKey ORDER BY encounter_ts) AS next_ts
    FROM encounters
  ),
  g AS (
    SELECT PatientDurableKey,
           DATE_DIFF('day', encounter_ts, next_ts) AS gap_days
    FROM ord WHERE next_ts IS NOT NULL
  )
  SELECT PatientDurableKey,
         COUNT(*) AS n_gaps,
         APPROX_QUANTILE(gap_days, 0.25) AS gap_q25,
         APPROX_QUANTILE(gap_days, 0.50) AS gap_median,
         APPROX_QUANTILE(gap_days, 0.75) AS gap_q75,
         AVG(gap_days)                   AS gap_mean,
         SUM(CASE WHEN gap_days <=  30 THEN 1 ELSE 0 END) AS n_gap_le30,
         SUM(CASE WHEN gap_days <=  90 THEN 1 ELSE 0 END) AS n_gap_le90,
         SUM(CASE WHEN gap_days > 180 THEN 1 ELSE 0 END) AS n_gap_gt180
  FROM g GROUP BY PatientDurableKey;")

log_note("4) diagnosis-anchored cohort: patients with any chronic condition encounter")
CHRONIC_GROUPS <- c("ICD-10-CM: I10", "ICD-10-CM: E11", "ICD-10-CM: N18", "ICD-10-CM: I48")
dbExecute(con, "DROP TABLE IF EXISTS chronic_index;")
dbExecute(con, sprintf("
  CREATE TABLE chronic_index AS
  WITH matched AS (
    SELECT e.PatientDurableKey, e.encounter_ts, d.GroupCode, d.GroupName
    FROM encounters e
    JOIN diagnosis_dedup d ON e.PrimaryDiagnosisKey = d.DiagnosisKey
    WHERE d.GroupCode IN (%s)
  )
  SELECT PatientDurableKey, GroupCode, ANY_VALUE(GroupName) AS GroupName,
         MIN(encounter_ts) AS index_ts
  FROM matched
  GROUP BY PatientDurableKey, GroupCode;",
  paste(sprintf("'%s'", CHRONIC_GROUPS), collapse = ", ")))

log_note("5) post-index follow-up metrics per (patient, chronic group)")
dbExecute(con, "DROP TABLE IF EXISTS chronic_followup;")
dbExecute(con, "
  CREATE TABLE chronic_followup AS
  WITH post AS (
    SELECT ci.PatientDurableKey, ci.GroupCode, ci.GroupName, ci.index_ts,
           e.encounter_ts, e.IsEdVisit, e.IsInpatientAdmission
    FROM chronic_index ci
    JOIN encounters e
      ON e.PatientDurableKey = ci.PatientDurableKey
     AND e.encounter_ts     >  ci.index_ts
  ),
  first_after AS (
    SELECT PatientDurableKey, GroupCode,
           MIN(encounter_ts) AS first_after_ts
    FROM post GROUP BY PatientDurableKey, GroupCode
  )
  SELECT ci.PatientDurableKey, ci.GroupCode, ci.GroupName, ci.index_ts,
         fa.first_after_ts,
         DATE_DIFF('day', ci.index_ts, fa.first_after_ts) AS days_to_next,
         (SELECT COUNT(*) FROM post p
           WHERE p.PatientDurableKey=ci.PatientDurableKey AND p.GroupCode=ci.GroupCode
             AND DATE_DIFF('day', ci.index_ts, p.encounter_ts) <= 30) AS n_visits_30d,
         (SELECT COUNT(*) FROM post p
           WHERE p.PatientDurableKey=ci.PatientDurableKey AND p.GroupCode=ci.GroupCode
             AND DATE_DIFF('day', ci.index_ts, p.encounter_ts) <= 90) AS n_visits_90d,
         (SELECT COUNT(*) FROM post p
           WHERE p.PatientDurableKey=ci.PatientDurableKey AND p.GroupCode=ci.GroupCode
             AND DATE_DIFF('day', ci.index_ts, p.encounter_ts) <= 180) AS n_visits_180d,
         (SELECT COUNT(*) FROM post p
           WHERE p.PatientDurableKey=ci.PatientDurableKey AND p.GroupCode=ci.GroupCode
             AND p.IsEdVisit=1
             AND DATE_DIFF('day', ci.index_ts, p.encounter_ts) <= 180) AS n_ed_180d
  FROM chronic_index ci
  LEFT JOIN first_after fa USING (PatientDurableKey, GroupCode);")

n_chronic <- dbGetQuery(con, "
  SELECT GroupCode, ANY_VALUE(GroupName) GroupName, COUNT(*) n_patients
  FROM chronic_index GROUP BY GroupCode;")
print(n_chronic); save_tbl(n_chronic, "journey_chronic_cohort_counts.csv")

log_note("6) assemble patient analytic table = patient_journey + gaps + transport + demographics")
dbExecute(con, "DROP TABLE IF EXISTS patient_analytic;")
dbExecute(con, "
  CREATE TABLE patient_analytic AS
  SELECT
    pj.*,
    pg.n_gaps, pg.gap_median, pg.gap_mean, pg.gap_q25, pg.gap_q75,
    pg.n_gap_le30, pg.n_gap_le90, pg.n_gap_gt180,
    pt.transport_status, pt.transport_yes, pt.transport_no,
    p.BirthYearBin, p.SexAtBirth, p.FirstRace, p.OmbRace, p.OmbEthnicity,
    p.MaritalStatus, p.MyChartStatus, p.SmokingStatus, p.VitalStatus,
    p.FipsCode,
    2026 - p.BirthYearBin AS age_proxy,
    t.Population AS block_population
  FROM patient_journey pj
  LEFT JOIN patient_gaps     pg USING (PatientDurableKey)
  LEFT JOIN patient_transport pt USING (PatientDurableKey)
  LEFT JOIN patients         p  USING (PatientDurableKey)
  LEFT JOIN tiger            t  ON p.FipsCode = t.FipsCode;")

ct <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM patient_analytic")$n
log_note("patient_analytic rows =", format(ct, big.mark = ","))

log_note("sanity: transport vs age, encounter count, gap median")
ss <- dbGetQuery(con, "
  SELECT transport_status,
         COUNT(*) AS n_patients,
         AVG(age_proxy) AS mean_age,
         APPROX_QUANTILE(age_proxy, 0.50) AS median_age,
         AVG(n_encounters) AS mean_enc,
         APPROX_QUANTILE(n_encounters, 0.50) AS median_enc,
         AVG(n_ed) AS mean_ed,
         APPROX_QUANTILE(gap_median, 0.50) AS median_gap_days,
         AVG(CAST(n_ed > 0 AS INTEGER)) AS pct_any_ed,
         AVG(CAST(n_inpatient > 0 AS INTEGER)) AS pct_any_inpat
  FROM patient_analytic
  GROUP BY transport_status
  ORDER BY n_patients DESC;")
print(ss); save_tbl(ss, "journey_patient_summary_by_transport.csv")

log_note("03_journey: done")
