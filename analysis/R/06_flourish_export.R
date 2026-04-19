source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/00_config.R")

FLOUR_DIR <- file.path(OUT_DIR, "flourish")
dir.create(FLOUR_DIR, recursive = TRUE, showWarnings = FALSE)

log_note("06_flourish_export: start")
con <- connect_db(read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

chk <- dbGetQuery(con, "
  SELECT COUNT(*) AS n FROM information_schema.tables
  WHERE table_schema = 'main' AND table_name = 'patient_analytic';")$n
if (chk == 0) {
  stop("Run analysis/R/03_journey.R first so patient_analytic exists.")
}

long <- dbGetQuery(con, "
WITH tpts AS (
  SELECT PatientDurableKey,
         CASE transport_status
           WHEN 'no_barrier' THEN 'No transport barrier'
           WHEN 'barrier'     THEN 'Transport barrier'
         END AS cohort
  FROM patient_analytic
  WHERE transport_status IN ('no_barrier', 'barrier')
),
ed_agg AS (
  SELECT
    CAST(EXTRACT(YEAR FROM e.encounter_ts) AS INTEGER) AS year,
    t.cohort,
    SUM(e.IsEdVisit)::DOUBLE AS n_ed
  FROM encounters e
  INNER JOIN tpts t ON e.PatientDurableKey = t.PatientDurableKey
  GROUP BY 1, 2
),
py_agg AS (
  SELECT
    years.yr AS year,
    t.cohort,
    SUM(
      CASE
        WHEN CAST(j.last_ts AS DATE) < make_date(years.yr, 1, 1) THEN 0.0
        WHEN CAST(j.first_ts AS DATE) > make_date(years.yr, 12, 31) THEN 0.0
        ELSE (date_diff('day',
          GREATEST(CAST(j.first_ts AS DATE), make_date(years.yr, 1, 1)),
          LEAST(CAST(j.last_ts AS DATE), make_date(years.yr, 12, 31))
        ) + 1.0)
      END
    ) / 365.25 AS person_years,
    COUNT(DISTINCT t.PatientDurableKey) AS n_patients_in_panel
  FROM tpts t
  INNER JOIN patient_journey j ON j.PatientDurableKey = t.PatientDurableKey
  CROSS JOIN unnest([2022, 2023, 2024, 2025]) AS years(yr)
  GROUP BY years.yr, t.cohort
),
any_ed AS (
  SELECT
    CAST(EXTRACT(YEAR FROM e.encounter_ts) AS INTEGER) AS year,
    t.cohort,
    e.PatientDurableKey,
    MAX(e.IsEdVisit) AS any_ed
  FROM encounters e
  INNER JOIN tpts t ON e.PatientDurableKey = t.PatientDurableKey
  GROUP BY 1, 2, 3
),
any_agg AS (
  SELECT year, cohort,
         COUNT(*)::DOUBLE AS n_patients_with_enc,
         SUM(any_ed)::DOUBLE AS n_patients_any_ed
  FROM any_ed
  GROUP BY year, cohort
)
SELECT
  e.year,
  e.cohort,
  'ed_per_person_year' AS metric,
  e.n_ed / NULLIF(p.person_years, 0) AS value,
  e.n_ed AS n_ed,
  p.person_years,
  p.n_patients_in_panel AS n_patients,
  a.n_patients_any_ed / NULLIF(a.n_patients_with_enc, 0) AS pct_any_ed
FROM ed_agg e
INNER JOIN py_agg p USING (year, cohort)
INNER JOIN any_agg a USING (year, cohort)
ORDER BY e.cohort, e.year;
")

out_main <- file.path(FLOUR_DIR, "flourish_transport_ed_by_year.csv")
fwrite(long, out_main)
log_note("wrote ", out_main, " (", nrow(long), " rows)")

slope <- long[long$year %in% c(2022L, 2025L), ]
out_slope <- file.path(FLOUR_DIR, "flourish_slope_ed_per_py_2022_2025.csv")
fwrite(slope, out_slope)
log_note("wrote ", out_slope, " (", nrow(slope), " rows) for two-point slope chart")

wide_py <- dcast(as.data.table(long), year ~ cohort, value.var = "value")
out_wide <- file.path(FLOUR_DIR, "flourish_slope_ed_per_py_wide.csv")
fwrite(wide_py, out_wide)
log_note("wrote ", out_wide, " (wide year x cohort for some Flourish templates)")

print(long)
log_note("06_flourish_export: done")
