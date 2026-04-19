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
ORDER BY s.cohort, y.yr
