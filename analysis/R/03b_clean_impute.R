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
source(file.path(ROOT, "analysis", "R", "functions.R"))

log_note("03b_clean_impute: start")

if (!file.exists(DB_PATH)) {
  log_note("03b_clean_impute: DuckDB database not found at", DB_PATH, "(skipping database update)")
} else {
  con <- connect_db(read_only = FALSE)
  on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  if (!dbExistsTable(con, "patient_analytic")) {
    log_note("03b_clean_impute: patient_analytic table not found in DuckDB. (Run 03_journey.R first)")
  } else {
    log_note("reading patient_analytic from DuckDB")
    pa_dt <- as.data.table(dbGetQuery(con, "SELECT * FROM patient_analytic;"))
    log_note("raw patient_analytic rows =", format(nrow(pa_dt), big.mark = ","))

    numeric_features <- intersect(
      c("age_proxy", "block_population", "n_encounters", "days_observed",
        "n_ed", "n_inpatient", "n_hospadm", "n_obs", "n_opf2f", "n_hod",
        "n_departments", "n_providers", "n_distinct_days", "gap_median",
        "gap_mean", "gap_q25", "gap_q75", "n_gaps", "n_gap_le30",
        "n_gap_le90", "n_gap_gt180"),
      names(pa_dt)
    )

    categorical_features <- intersect(
      c("SexAtBirth", "FirstRace", "OmbRace", "OmbEthnicity",
        "MaritalStatus", "MyChartStatus", "SmokingStatus", "VitalStatus"),
      names(pa_dt)
    )

    log_note("executing automated outlier capping and missing data imputation")
    pa_clean <- clean_pipeline_features(
      dt = pa_dt,
      numeric_cols = numeric_features,
      categorical_cols = categorical_features,
      impute_numeric = "median",
      impute_categorical = "mode",
      outlier_method = "iqr",
      outlier_threshold = 1.5,
      outlier_action = "cap",
      add_indicators = TRUE,
      in_place = FALSE
    )

    summary_tbl <- summarize_cleaning(
      dt_raw = pa_dt,
      dt_clean = pa_clean,
      cols = c(numeric_features, categorical_features)
    )
    save_tbl(summary_tbl, "cleaning_imputation_outlier_summary.csv")
    log_note("saved cleaning audit summary to tables/cleaning_imputation_outlier_summary.csv")
    print(summary_tbl)

    log_note("writing patient_analytic_clean to DuckDB")
    dbExecute(con, "DROP TABLE IF EXISTS patient_analytic_clean;")
    dbWriteTable(con, "patient_analytic_clean", pa_clean)
    log_note("patient_analytic_clean created successfully with",
             format(nrow(pa_clean), big.mark = ","), "rows")
  }
}

log_note("03b_clean_impute: done")
