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

log_note("04_analyses: start")
con <- connect_db(read_only = FALSE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

log_note("headline journey metrics by transport status (screened patients only)")
headline <- dbGetQuery(con, "
  SELECT transport_status,
         COUNT(*)                              AS n_patients,
         AVG(n_encounters)                     AS mean_enc,
         APPROX_QUANTILE(n_encounters, 0.50)   AS median_enc,
         AVG(n_ed)                             AS mean_ed,
         APPROX_QUANTILE(n_ed, 0.50)           AS median_ed,
         AVG(CAST(n_ed > 0        AS INTEGER)) AS pct_any_ed,
         AVG(CAST(n_inpatient > 0 AS INTEGER)) AS pct_any_inpat,
         AVG(CAST(n_obs       > 0 AS INTEGER)) AS pct_any_obs,
         AVG(age_proxy)                        AS mean_age,
         APPROX_QUANTILE(gap_median, 0.50)     AS median_gap_days,
         APPROX_QUANTILE(gap_q75,    0.50)     AS median_gap_q75
  FROM patient_analytic
  WHERE transport_status IS NOT NULL
  GROUP BY transport_status
  ORDER BY CASE transport_status WHEN 'no_barrier' THEN 1 WHEN 'barrier' THEN 2 ELSE 3 END;")
print(headline); save_tbl(headline, "an_headline_by_transport.csv")

log_note("setting mix per patient: share of encounters in ED/inpatient/outpatient f2f/other")
setting_mix <- dbGetQuery(con, "
  WITH pm AS (
    SELECT transport_status,
           SUM(CAST(n_ed AS DOUBLE))           / NULLIF(SUM(n_encounters),0) AS share_ed,
           SUM(CAST(n_inpatient AS DOUBLE))    / NULLIF(SUM(n_encounters),0) AS share_inpatient,
           SUM(CAST(n_opf2f  AS DOUBLE))       / NULLIF(SUM(n_encounters),0) AS share_opf2f,
           SUM(CAST(n_hod AS DOUBLE))          / NULLIF(SUM(n_encounters),0) AS share_hod,
           SUM(CAST(n_obs AS DOUBLE))          / NULLIF(SUM(n_encounters),0) AS share_obs,
           SUM(n_encounters)                                                 AS total_encs,
           COUNT(*)                                                          AS n_patients
    FROM patient_analytic
    WHERE transport_status IS NOT NULL
    GROUP BY transport_status
  )
  SELECT * FROM pm;")
print(setting_mix); save_tbl(setting_mix, "an_setting_mix_by_transport.csv")

log_note("chronic condition follow-up: time to next encounter by transport status")
chronic_fu <- dbGetQuery(con, "
  SELECT cf.GroupCode, ANY_VALUE(cf.GroupName) AS GroupName,
         COALESCE(pa.transport_status, 'not_screened') AS transport_status,
         COUNT(*) AS n_patients,
         APPROX_QUANTILE(days_to_next, 0.25)       AS days_q25,
         APPROX_QUANTILE(days_to_next, 0.50)       AS days_median,
         APPROX_QUANTILE(days_to_next, 0.75)       AS days_q75,
         AVG(CAST(days_to_next <= 30  AS INTEGER)) AS pct_fu_30,
         AVG(CAST(days_to_next <= 90  AS INTEGER)) AS pct_fu_90,
         AVG(CAST(days_to_next <= 180 AS INTEGER)) AS pct_fu_180,
         AVG(n_visits_90d)                         AS mean_visits_90d,
         AVG(n_ed_180d)                            AS mean_ed_180d,
         AVG(CAST(n_ed_180d > 0 AS INTEGER))       AS pct_any_ed_180
  FROM chronic_followup cf
  LEFT JOIN patient_analytic pa USING (PatientDurableKey)
  GROUP BY cf.GroupCode, COALESCE(pa.transport_status, 'not_screened');")
print(chronic_fu); save_tbl(chronic_fu, "an_chronic_followup_by_transport.csv")

log_note("ED visits per year at risk, by transport status (accounting for observation window)")
ed_rate <- dbGetQuery(con, "
  SELECT transport_status,
         COUNT(*) n_patients,
         SUM(n_ed)                              AS total_ed,
         SUM(n_encounters)                      AS total_enc,
         SUM(GREATEST(days_observed, 1))        AS total_days_observed,
         SUM(n_ed) * 365.25
           / NULLIF(SUM(GREATEST(days_observed,1)),0) AS ed_per_person_year,
         SUM(n_inpatient) * 365.25
           / NULLIF(SUM(GREATEST(days_observed,1)),0) AS inpat_per_person_year
  FROM patient_analytic
  WHERE transport_status IS NOT NULL
  GROUP BY transport_status;")
print(ed_rate); save_tbl(ed_rate, "an_annualized_rates_by_transport.csv")

log_note("logistic regression: any ED visit ~ transport + age + sex (approx via GLM in R)")

pa_df <- as.data.table(dbGetQuery(con, "
  SELECT PatientDurableKey,
         CAST(n_ed > 0 AS INTEGER) AS any_ed,
         CAST(n_inpatient > 0 AS INTEGER) AS any_inpat,
         transport_status,
         age_proxy,
         SexAtBirth
  FROM patient_analytic
  WHERE transport_status IN ('barrier','no_barrier')
    AND age_proxy IS NOT NULL;"))

pa_df[, transport := relevel(factor(transport_status,
                                    levels = c("no_barrier","barrier")),
                             ref = "no_barrier")]
pa_df[, sex := factor(ifelse(SexAtBirth %in% c("Male","Female"), SexAtBirth, "Other/Unknown"))]

m_ed <- glm(any_ed ~ transport + age_proxy + sex, data = pa_df, family = binomial())
m_in <- glm(any_inpat ~ transport + age_proxy + sex, data = pa_df, family = binomial())

coef_or <- function(m, label) {
  co <- summary(m)$coefficients
  out <- data.table(term = rownames(co),
                    est = co[, "Estimate"],
                    se  = co[, "Std. Error"],
                    z   = co[, "z value"],
                    p   = co[, "Pr(>|z|)"])
  out[, odds_ratio := exp(est)]
  out[, or_lo := exp(est - 1.96 * se)]
  out[, or_hi := exp(est + 1.96 * se)]
  out[, model := label]
  out[]
}

or_tab <- rbindlist(list(coef_or(m_ed, "any_ED"),
                         coef_or(m_in, "any_inpatient")))
print(or_tab)
save_tbl(or_tab, "an_logit_or_transport.csv")

log_note("04_analyses: done")
