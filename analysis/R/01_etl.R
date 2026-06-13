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

log_note("01_etl: start")
stopifnot(all(file.exists(unlist(CSV))))

if (file.exists(DB_PATH)) file.remove(DB_PATH)
wal <- paste0(DB_PATH, ".wal"); if (file.exists(wal)) file.remove(wal)

con <- connect_db(read_only = FALSE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

dbExecute(con, "PRAGMA threads=4;")
dbExecute(con, "PRAGMA memory_limit='6GB';")
dbExecute(con, sprintf("PRAGMA temp_directory='%s';", file.path(CACHE_DIR, "duck_tmp")))

t_sql <- function(sql, label = "") {
  t0 <- Sys.time()
  dbExecute(con, sql)
  dt <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  log_note(sprintf("  [%5ss] %s", dt, label))
}

log_note("create patients")
t_sql(sprintf("
  CREATE OR REPLACE TABLE patients AS
  SELECT
    DurableKey::BIGINT                         AS PatientDurableKey,
    TRY_CAST(PatientBirthYearBin AS INTEGER)   AS BirthYearBin,
    SexAssignedAtBirth                         AS SexAtBirth,
    FirstRace, OmbRace, OmbEthnicity,
    MaritalStatus, MyChartStatus, SmokingStatus, VitalStatus,
    CAST(CensusBlockGroupFipsCode AS VARCHAR)  AS FipsCode
  FROM read_csv_auto('%s', HEADER=TRUE, nullstr=['NA','*Unspecified','*Unknown']);", CSV$patients), "patients")

log_note("create diagnosis")
t_sql(sprintf("
  CREATE OR REPLACE TABLE diagnosis AS
  SELECT TRY_CAST(DiagnosisKey AS BIGINT) AS DiagnosisKey,
         DiagnosisValue, DiagnosisName, GroupCode, GroupName
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$diagnosis), "diagnosis")

log_note("create departments")
t_sql(sprintf("
  CREATE OR REPLACE TABLE departments AS
  SELECT TRY_CAST(DepartmentKey AS BIGINT) AS DepartmentKey,
         DepartmentName, DepartmentSpecialty, DepartmentType,
         City, County,
         CAST(PostalCode  AS VARCHAR) AS PostalCode,
         CAST(CensusTract AS VARCHAR) AS DeptCensusTract
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$departments), "departments")

log_note("create providers")
t_sql(sprintf("
  CREATE OR REPLACE TABLE providers AS
  SELECT TRY_CAST(DurableKey AS BIGINT) AS ProviderDurableKey,
         ClinicianTitle, Type AS ProviderType,
         PrimarySpecialty, PrimaryDepartment,
         OfficeCity, CAST(OfficePostalCode AS VARCHAR) AS OfficePostalCode
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$providers), "providers")

log_note("create tiger")
t_sql(sprintf("
  CREATE OR REPLACE TABLE tiger AS
  SELECT CAST(GEOID AS VARCHAR) AS FipsCode,
         TRY_CAST(CENTLAT AS DOUBLE) AS lat,
         TRY_CAST(CENTLON AS DOUBLE)  AS lon,
         TRY_CAST(PopulationValue AS INTEGER) AS Population
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$tiger), "tiger")

log_note("create sdoh")
t_sql(sprintf("
  CREATE OR REPLACE TABLE sdoh AS
  SELECT TRY_CAST(EncounterKey AS BIGINT)      AS EncounterKey,
         TRY_CAST(PatientDurableKey AS BIGINT) AS PatientDurableKey,
         Domain,
         DisplayName,
         AnswerText
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$sdoh), "sdoh")

log_note("create encounters (lean; parse dates)")
t_sql(sprintf("
  CREATE OR REPLACE TABLE encounters AS
  SELECT
    TRY_CAST(EncounterKey AS BIGINT)          AS EncounterKey,
    TRY_CAST(PatientDurableKey AS BIGINT)     AS PatientDurableKey,
    TRY_CAST(DepartmentKey AS BIGINT)         AS DepartmentKey,
    TRY_CAST(ProviderDurableKey AS BIGINT)    AS ProviderDurableKey,
    TRY_CAST(PrimaryDiagnosisKey AS BIGINT)   AS PrimaryDiagnosisKey,
    Type,
    VisitType,
    VisitTypeDescription,
    AdmissionType,
    AdmissionSource,
    TRY_CAST(AdmissionInstant AS TIMESTAMP)   AS AdmissionInstant,
    TRY_CAST(DischargeInstant AS TIMESTAMP)   AS DischargeInstant,
    TRY_CAST(Date AS DATE)                    AS EncounterDate,
    CAST(IsEdVisit AS INTEGER)                AS IsEdVisit,
    CAST(IsHospitalAdmission AS INTEGER)      AS IsHospitalAdmission,
    CAST(IsHospitalOutpatientVisit AS INTEGER) AS IsHospitalOutpatientVisit,
    CAST(IsInpatientAdmission AS INTEGER)     AS IsInpatientAdmission,
    CAST(IsObservation AS INTEGER)            AS IsObservation,
    CAST(IsOutpatientFaceToFaceVisit AS INTEGER) AS IsOutpatientFaceToFaceVisit,
    COALESCE(TRY_CAST(AdmissionInstant AS TIMESTAMP),
             CAST(TRY_CAST(Date AS DATE) AS TIMESTAMP)) AS encounter_ts
  FROM read_csv_auto('%s', HEADER=TRUE);", CSV$encounters), "encounters")

log_note("row counts")
rc <- dbGetQuery(con, "
  SELECT 'patients'    AS tbl, COUNT(*) n FROM patients    UNION ALL
  SELECT 'encounters',   COUNT(*)         FROM encounters   UNION ALL
  SELECT 'diagnosis',    COUNT(*)         FROM diagnosis    UNION ALL
  SELECT 'departments',  COUNT(*)         FROM departments  UNION ALL
  SELECT 'providers',    COUNT(*)         FROM providers    UNION ALL
  SELECT 'sdoh',         COUNT(*)         FROM sdoh         UNION ALL
  SELECT 'tiger',        COUNT(*)         FROM tiger
  ORDER BY tbl;")
print(rc)
save_tbl(rc, "qa_row_counts.csv")

log_note("QA: join diagnostics")
qa_list <- list()

qa_list$dup_encounter <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_dup FROM (
    SELECT EncounterKey FROM encounters GROUP BY EncounterKey HAVING COUNT(*)>1
  );")

qa_list$diag_join <- dbGetQuery(con, "
  SELECT
    COUNT(*)                                                            AS n_enc,
    SUM(CASE WHEN e.PrimaryDiagnosisKey IS NULL THEN 1 ELSE 0 END)      AS n_null_key,
    SUM(CASE WHEN e.PrimaryDiagnosisKey IS NOT NULL
             AND d.DiagnosisKey IS NULL THEN 1 ELSE 0 END)              AS n_unmatched_nonnull,
    SUM(CASE WHEN d.DiagnosisKey IS NOT NULL THEN 1 ELSE 0 END)         AS n_matched
  FROM encounters e
  LEFT JOIN diagnosis d ON e.PrimaryDiagnosisKey = d.DiagnosisKey;")

qa_list$patient_join <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_enc,
         SUM(CASE WHEN p.PatientDurableKey IS NULL THEN 1 ELSE 0 END) AS n_unmatched
  FROM encounters e
  LEFT JOIN patients p ON e.PatientDurableKey = p.PatientDurableKey;")

qa_list$dept_join <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_enc,
         SUM(CASE WHEN d.DepartmentKey IS NULL THEN 1 ELSE 0 END) AS n_unmatched
  FROM encounters e
  LEFT JOIN departments d ON e.DepartmentKey = d.DepartmentKey;")

qa_list$sdoh_enc_join <- dbGetQuery(con, "
  SELECT COUNT(*) AS n_sdoh_rows,
         SUM(CASE WHEN e.EncounterKey IS NULL THEN 1 ELSE 0 END) AS n_unmatched_encounter
  FROM sdoh s LEFT JOIN encounters e ON s.EncounterKey = e.EncounterKey;")

qa_list$date_range <- dbGetQuery(con, "
  SELECT MIN(encounter_ts) AS min_ts, MAX(encounter_ts) AS max_ts,
         SUM(CASE WHEN encounter_ts IS NULL THEN 1 ELSE 0 END) AS n_missing_ts,
         COUNT(*) AS n FROM encounters;")

qa_list$type_mix <- dbGetQuery(con, "
  SELECT Type, COUNT(*) AS n FROM encounters GROUP BY Type ORDER BY n DESC;")

qa_list$bool_mix <- dbGetQuery(con, "
  SELECT SUM(IsEdVisit) n_ed, SUM(IsHospitalAdmission) n_hosp_adm,
         SUM(IsHospitalOutpatientVisit) n_hod, SUM(IsInpatientAdmission) n_inpatient,
         SUM(IsObservation) n_obs, SUM(IsOutpatientFaceToFaceVisit) n_opf2f,
         COUNT(*) n_total FROM encounters;")

for (nm in names(qa_list)) {
  save_tbl(qa_list[[nm]], sprintf("qa_%s.csv", nm))
  cat(sprintf("QA %-16s :\n", nm)); print(qa_list[[nm]])
}

log_note("diagnosis dedup (some DiagnosisKey rows duplicate -> pick first row per key)")
t_sql("
  CREATE OR REPLACE TABLE diagnosis_dedup AS
  SELECT DiagnosisKey, ANY_VALUE(DiagnosisValue) AS DiagnosisValue,
         ANY_VALUE(DiagnosisName)  AS DiagnosisName,
         ANY_VALUE(GroupCode)      AS GroupCode,
         ANY_VALUE(GroupName)      AS GroupName
  FROM diagnosis GROUP BY DiagnosisKey;", "diagnosis_dedup")

log_note("skipping indexes (rely on DuckDB hash joins to avoid v1.3 index segfault)")

log_note("01_etl: done.")
