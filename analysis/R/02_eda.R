source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/00_config.R")

log_note("02_eda: start")
con <- connect_db(read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

log_note("top diagnosis groups (by encounter count, matched rows only)")
top_groups <- dbGetQuery(con, "
  SELECT d.GroupCode, ANY_VALUE(d.GroupName) AS GroupName,
         COUNT(*) AS n_enc, COUNT(DISTINCT e.PatientDurableKey) AS n_patients
  FROM encounters e
  JOIN diagnosis_dedup d ON e.PrimaryDiagnosisKey = d.DiagnosisKey
  WHERE d.GroupCode IS NOT NULL
  GROUP BY d.GroupCode
  ORDER BY n_enc DESC
  LIMIT 40;")
save_tbl(top_groups, "eda_top_diag_groups.csv")

log_note("top diagnosis values (specific ICD-10)")
top_dx <- dbGetQuery(con, "
  SELECT d.DiagnosisValue, ANY_VALUE(d.DiagnosisName) AS DiagnosisName,
         COUNT(*) AS n_enc, COUNT(DISTINCT e.PatientDurableKey) AS n_patients
  FROM encounters e
  JOIN diagnosis_dedup d ON e.PrimaryDiagnosisKey = d.DiagnosisKey
  WHERE d.DiagnosisValue IS NOT NULL
  GROUP BY d.DiagnosisValue
  ORDER BY n_enc DESC
  LIMIT 60;")
save_tbl(top_dx, "eda_top_diag_values.csv")

log_note("encounter volume by year, DepartmentType, setting flags")
by_year <- dbGetQuery(con, "
  SELECT EXTRACT(YEAR FROM encounter_ts) AS yr,
         COUNT(*) AS n_enc,
         SUM(IsEdVisit) AS n_ed, SUM(IsHospitalAdmission) AS n_hospadm,
         SUM(IsInpatientAdmission) AS n_inpat, SUM(IsOutpatientFaceToFaceVisit) AS n_opf2f,
         SUM(IsHospitalOutpatientVisit) AS n_hod
  FROM encounters GROUP BY yr ORDER BY yr;")
save_tbl(by_year, "eda_encounters_by_year.csv"); print(by_year)

by_dept <- dbGetQuery(con, "
  SELECT d.DepartmentType, COUNT(*) n_enc,
         COUNT(DISTINCT e.PatientDurableKey) n_patients,
         SUM(e.IsEdVisit) n_ed
  FROM encounters e LEFT JOIN departments d ON e.DepartmentKey = d.DepartmentKey
  GROUP BY d.DepartmentType ORDER BY n_enc DESC;")
save_tbl(by_dept, "eda_encounters_by_depttype.csv"); print(by_dept)

log_note("SDOH domain coverage")
sdoh_domains <- dbGetQuery(con, "
  SELECT COALESCE(Domain, '(missing)') AS Domain,
         COUNT(*) AS n_rows,
         COUNT(DISTINCT PatientDurableKey) AS n_patients
  FROM sdoh GROUP BY COALESCE(Domain, '(missing)')
  ORDER BY n_rows DESC;")
save_tbl(sdoh_domains, "eda_sdoh_domain_coverage.csv"); print(sdoh_domains)

log_note("SDOH per-patient answers (distinct domains) among patients with any answer")
sdoh_patient_coverage <- dbGetQuery(con, "
  WITH pat_dom AS (
    SELECT PatientDurableKey, Domain
    FROM sdoh
    WHERE Domain IS NOT NULL
    GROUP BY PatientDurableKey, Domain
  )
  SELECT Domain, COUNT(DISTINCT PatientDurableKey) AS n_patients
  FROM pat_dom GROUP BY Domain ORDER BY n_patients DESC;")
save_tbl(sdoh_patient_coverage, "eda_sdoh_patients_per_domain.csv")
print(sdoh_patient_coverage)

log_note("geographic missingness on patients (FIPS code)")
fips_cov <- dbGetQuery(con, "
  SELECT CASE
           WHEN FipsCode IS NULL OR FipsCode = '' OR FipsCode LIKE '*%%' THEN 'unspecified'
           ELSE 'fips_present'
         END AS fips_state,
         COUNT(*) AS n_patients
  FROM patients GROUP BY fips_state;")
save_tbl(fips_cov, "eda_fips_coverage.csv"); print(fips_cov)

fips_match <- dbGetQuery(con, "
  SELECT
    COUNT(*) AS n_patients_with_fips,
    SUM(CASE WHEN t.FipsCode IS NULL THEN 1 ELSE 0 END) AS n_without_tiger
  FROM patients p
  LEFT JOIN tiger t ON p.FipsCode = t.FipsCode
  WHERE p.FipsCode IS NOT NULL AND p.FipsCode NOT LIKE '*%%' AND p.FipsCode <> '';")
save_tbl(fips_match, "eda_fips_tiger_match.csv"); print(fips_match)

log_note("patients per birth-year bin")
age_cov <- dbGetQuery(con, "
  SELECT BirthYearBin, COUNT(*) n_patients
  FROM patients GROUP BY BirthYearBin ORDER BY BirthYearBin;")
save_tbl(age_cov, "eda_patients_by_birthyearbin.csv")

log_note("per-patient encounter count distribution")
enc_per_pt <- dbGetQuery(con, "
  WITH pc AS (
    SELECT PatientDurableKey, COUNT(*) AS n_enc FROM encounters GROUP BY PatientDurableKey
  )
  SELECT
    COUNT(*) AS n_patients,
    MIN(n_enc) AS min_enc,
    APPROX_QUANTILE(n_enc, 0.25) AS q25,
    APPROX_QUANTILE(n_enc, 0.50) AS median,
    APPROX_QUANTILE(n_enc, 0.75) AS q75,
    APPROX_QUANTILE(n_enc, 0.95) AS q95,
    MAX(n_enc) AS max_enc,
    AVG(n_enc) AS mean_enc
  FROM pc;")
save_tbl(enc_per_pt, "eda_enc_per_patient.csv"); print(enc_per_pt)

log_note("SDOH coverage: patients with any SDOH response + any encounter")
sdoh_enc_patient_overlap <- dbGetQuery(con, "
  WITH any_sdoh AS (SELECT DISTINCT PatientDurableKey FROM sdoh WHERE PatientDurableKey IS NOT NULL),
       any_enc  AS (SELECT DISTINCT PatientDurableKey FROM encounters)
  SELECT
    (SELECT COUNT(*) FROM any_sdoh)                                         AS n_patients_any_sdoh,
    (SELECT COUNT(*) FROM any_enc)                                          AS n_patients_any_enc,
    (SELECT COUNT(*) FROM any_sdoh INNER JOIN any_enc USING (PatientDurableKey)) AS n_overlap;")
save_tbl(sdoh_enc_patient_overlap, "eda_sdoh_encounter_overlap.csv"); print(sdoh_enc_patient_overlap)

log_note("top transportation answers (domain = Transportation Needs)")
transp <- dbGetQuery(con, "
  SELECT DisplayName, AnswerText, COUNT(*) n
  FROM sdoh WHERE Domain = 'Transportation Needs'
  GROUP BY DisplayName, AnswerText ORDER BY n DESC LIMIT 30;")
save_tbl(transp, "eda_transportation_answers.csv")

log_note("02_eda: done")
