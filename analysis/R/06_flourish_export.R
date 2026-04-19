.libPaths(c("~/R/datafest_libs", .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"
OUT_DIR <- file.path(ROOT, "analysis", "output")
CACHE_DIR <- path.expand("~/.datafest_cache")
DB_PATH <- file.path(CACHE_DIR, "datafest.duckdb")
DIR_ANNUAL <- file.path(OUT_DIR, "flourish", "annual")
DIR_Q <- file.path(OUT_DIR, "flourish", "quarterly")
for (d in c(DIR_ANNUAL, DIR_Q)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

cat("[flourish] connecting ", DB_PATH, "\n", sep = "")
con <- dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

annual_sql <- "
WITH cohort AS (
  SELECT
    PatientDurableKey,
    CASE transport_status
      WHEN 'no_barrier' THEN 'No transport barrier'
      WHEN 'barrier' THEN 'Transport barrier'
    END AS cohort
  FROM patient_analytic
  WHERE transport_status IN ('no_barrier', 'barrier')
),
bounds AS (
  SELECT
    e.PatientDurableKey,
    CAST(MIN(e.encounter_ts) AS DATE) AS first_d,
    CAST(MAX(e.encounter_ts) AS DATE) AS last_d
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  GROUP BY e.PatientDurableKey
),
yr_grid AS (
  SELECT * FROM (VALUES (2022), (2023), (2024), (2025)) AS t(yr)
),
py_long AS (
  SELECT
    c.cohort,
    y.yr,
    c.PatientDurableKey,
    CASE
      WHEN GREATEST(b.first_d, MAKE_DATE(y.yr, 1, 1)) <= LEAST(b.last_d, MAKE_DATE(y.yr, 12, 31)) THEN (
        DATE_DIFF(
          'day',
          GREATEST(b.first_d, MAKE_DATE(y.yr, 1, 1)),
          LEAST(b.last_d, MAKE_DATE(y.yr, 12, 31))
        ) + 1
      ) / 365.25
      ELSE 0.0
    END AS py
  FROM cohort c
  INNER JOIN bounds b ON c.PatientDurableKey = b.PatientDurableKey
  CROSS JOIN yr_grid y
),
py_agg AS (
  SELECT cohort, yr, SUM(py) AS person_years
  FROM py_long
  GROUP BY cohort, yr
),
ed_agg AS (
  SELECT
    c.cohort,
    EXTRACT(YEAR FROM e.encounter_ts)::INTEGER AS yr,
    SUM(CASE WHEN e.IsEdVisit THEN 1 ELSE 0 END) AS n_ed
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  WHERE e.encounter_ts IS NOT NULL
    AND CAST(e.encounter_ts AS DATE) >= DATE '2022-01-01'
    AND CAST(e.encounter_ts AS DATE) <= DATE '2025-12-31'
  GROUP BY c.cohort, EXTRACT(YEAR FROM e.encounter_ts)::INTEGER
),
ed_any AS (
  SELECT
    c.cohort,
    EXTRACT(YEAR FROM e.encounter_ts)::INTEGER AS yr,
    COUNT(DISTINCT e.PatientDurableKey) AS n_any_ed
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  WHERE e.encounter_ts IS NOT NULL
    AND e.IsEdVisit
    AND CAST(e.encounter_ts AS DATE) >= DATE '2022-01-01'
    AND CAST(e.encounter_ts AS DATE) <= DATE '2025-12-31'
  GROUP BY c.cohort, EXTRACT(YEAR FROM e.encounter_ts)::INTEGER
),
sizes AS (
  SELECT cohort, COUNT(*) AS n_patients
  FROM cohort
  GROUP BY cohort
)
SELECT
  y.yr AS year,
  s.cohort,
  'ed_per_person_year' AS metric,
  COALESCE(e.n_ed, 0)::DOUBLE * 1.0 / NULLIF(p.person_years, 0) AS value,
  COALESCE(e.n_ed, 0)::BIGINT AS n_ed,
  p.person_years,
  sz.n_patients,
  COALESCE(a.n_any_ed, 0)::DOUBLE / NULLIF(sz.n_patients, 0) AS pct_any_ed
FROM yr_grid y
CROSS JOIN (SELECT DISTINCT cohort FROM cohort) s
LEFT JOIN py_agg p ON p.cohort = s.cohort AND p.yr = y.yr
LEFT JOIN ed_agg e ON e.cohort = s.cohort AND e.yr = y.yr
LEFT JOIN sizes sz ON sz.cohort = s.cohort
LEFT JOIN ed_any a ON a.cohort = s.cohort AND a.yr = y.yr
ORDER BY s.cohort, y.yr;
"

quarterly_sql <- "
WITH cohort AS (
  SELECT
    PatientDurableKey,
    CASE transport_status
      WHEN 'no_barrier' THEN 'No transport barrier'
      WHEN 'barrier' THEN 'Transport barrier'
    END AS cohort
  FROM patient_analytic
  WHERE transport_status IN ('no_barrier', 'barrier')
),
bounds AS (
  SELECT
    e.PatientDurableKey,
    CAST(MIN(e.encounter_ts) AS DATE) AS first_d,
    CAST(MAX(e.encounter_ts) AS DATE) AS last_d
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  GROUP BY e.PatientDurableKey
),
qgrid AS (
  SELECT
    CAST(qs AS DATE) AS qstart,
    CAST(CAST(qs AS DATE) + INTERVAL 3 MONTH - INTERVAL 1 DAY AS DATE) AS qend,
    EXTRACT(YEAR FROM qs)::INTEGER AS yr,
    EXTRACT(QUARTER FROM qs)::INTEGER AS q
  FROM generate_series(
    TIMESTAMP '2022-01-01 00:00:00',
    TIMESTAMP '2025-10-01 00:00:00',
    INTERVAL '3 months'
  ) AS gs(qs)
),
py_long AS (
  SELECT
    c.cohort,
    g.yr,
    g.q,
    g.qstart,
    c.PatientDurableKey,
    CASE
      WHEN GREATEST(b.first_d, g.qstart) <= LEAST(b.last_d, g.qend) THEN (
        DATE_DIFF('day', GREATEST(b.first_d, g.qstart), LEAST(b.last_d, g.qend)) + 1
      ) / 365.25
      ELSE 0.0
    END AS py
  FROM cohort c
  INNER JOIN bounds b ON c.PatientDurableKey = b.PatientDurableKey
  CROSS JOIN qgrid g
),
py_agg AS (
  SELECT cohort, yr, q, qstart, SUM(py) AS person_years
  FROM py_long
  GROUP BY cohort, yr, q, qstart
),
ed_agg AS (
  SELECT
    c.cohort,
    EXTRACT(YEAR FROM e.encounter_ts)::INTEGER AS yr,
    EXTRACT(QUARTER FROM e.encounter_ts)::INTEGER AS q,
    SUM(CASE WHEN e.IsEdVisit THEN 1 ELSE 0 END) AS n_ed
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  WHERE e.encounter_ts IS NOT NULL
    AND CAST(e.encounter_ts AS DATE) >= DATE '2022-01-01'
    AND CAST(e.encounter_ts AS DATE) <= DATE '2025-12-31'
  GROUP BY c.cohort, EXTRACT(YEAR FROM e.encounter_ts)::INTEGER, EXTRACT(QUARTER FROM e.encounter_ts)::INTEGER
),
ed_any AS (
  SELECT
    c.cohort,
    EXTRACT(YEAR FROM e.encounter_ts)::INTEGER AS yr,
    EXTRACT(QUARTER FROM e.encounter_ts)::INTEGER AS q,
    COUNT(DISTINCT e.PatientDurableKey) AS n_any_ed
  FROM encounters e
  INNER JOIN cohort c ON e.PatientDurableKey = c.PatientDurableKey
  WHERE e.encounter_ts IS NOT NULL
    AND e.IsEdVisit
    AND CAST(e.encounter_ts AS DATE) >= DATE '2022-01-01'
    AND CAST(e.encounter_ts AS DATE) <= DATE '2025-12-31'
  GROUP BY c.cohort, EXTRACT(YEAR FROM e.encounter_ts)::INTEGER, EXTRACT(QUARTER FROM e.encounter_ts)::INTEGER
),
sizes AS (
  SELECT cohort, COUNT(*) AS n_patients
  FROM cohort
  GROUP BY cohort
),
grid AS (
  SELECT DISTINCT yr, q, qstart FROM qgrid
)
SELECT
  g.yr AS year,
  g.q AS quarter,
  g.qstart AS period_start,
  CAST(g.yr AS DOUBLE) + (CAST(g.q AS DOUBLE) - 1) / 4.0 AS t,
  (strftime(g.qstart, '%y') || ' Q' || CAST(g.q AS VARCHAR)) AS period_label,
  s.cohort,
  'ed_per_person_year' AS metric,
  COALESCE(e.n_ed, 0)::DOUBLE * 1.0 / NULLIF(p.person_years, 0) AS value,
  COALESCE(e.n_ed, 0)::BIGINT AS n_ed,
  p.person_years,
  sz.n_patients,
  COALESCE(a.n_any_ed, 0)::DOUBLE / NULLIF(sz.n_patients, 0) AS pct_any_ed
FROM grid g
CROSS JOIN (SELECT DISTINCT cohort FROM cohort) s
LEFT JOIN py_agg p ON p.cohort = s.cohort AND p.yr = g.yr AND p.q = g.q
LEFT JOIN ed_agg e ON e.cohort = s.cohort AND e.yr = g.yr AND e.q = g.q
LEFT JOIN sizes sz ON sz.cohort = s.cohort
LEFT JOIN ed_any a ON a.cohort = s.cohort AND a.yr = g.yr AND a.q = g.q
ORDER BY s.cohort, g.yr, g.q;
"

annual <- as.data.table(dbGetQuery(con, annual_sql))
quarterly <- as.data.table(dbGetQuery(con, quarterly_sql))

fwrite(annual, file.path(DIR_ANNUAL, "flourish_transport_ed_by_year.csv"))
fwrite(quarterly, file.path(DIR_Q, "flourish_transport_ed_by_quarter.csv"))

cat(
  "[flourish] wrote ", nrow(annual), " rows → ",
  file.path(DIR_ANNUAL, "flourish_transport_ed_by_year.csv"), "\n",
  "[flourish] wrote ", nrow(quarterly), " rows → ",
  file.path(DIR_Q, "flourish_transport_ed_by_quarter.csv"), "\n",
  sep = ""
)
