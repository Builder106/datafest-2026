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

log_note("04b_model_evaluation: retrospective patient-level cross-validation")
con <- connect_db(read_only = TRUE)
# Always read raw features: global cleaning would leak held-out information.
evaluation_data <- tryCatch(as.data.table(dbGetQuery(con, "
  SELECT PatientDurableKey, age_proxy, SexAtBirth, transport_status,
         CAST(n_ed > 0 AS INTEGER) AS any_ed,
         CAST(n_inpatient > 0 AS INTEGER) AS any_inpatient
  FROM patient_analytic
  WHERE transport_status IN ('barrier', 'no_barrier')
  ORDER BY PatientDurableKey;")),
  finally = dbDisconnect(con, shutdown = TRUE))

evaluation_data[, transport_barrier := as.integer(transport_status == "barrier")]
# Fixed encoding: other/unknown sex is the reference; no fitted full-cohort encoder.
evaluation_data[, sex_female := as.integer(!is.na(SexAtBirth) & SexAtBirth == "Female")]
evaluation_data[, sex_male := as.integer(!is.na(SexAtBirth) & SexAtBirth == "Male")]
evaluation_features <- c("age_proxy", "transport_barrier", "sex_female", "sex_male")

for (outcome in c("any_ed", "any_inpatient")) {
  cohort <- evaluation_data[!is.na(get(outcome))]
  log_note("evaluating", outcome, "on", nrow(cohort), "patients; missing outcomes excluded =",
           nrow(evaluation_data) - nrow(cohort))
  evaluation <- evaluate_ensemble_models(cohort, outcome, evaluation_features)
  prefix <- paste0("model_", outcome, "_")
  for (name in c("fold_metrics", "summary", "permutation_importance", "feature_importance")) {
    save_tbl(evaluation[[name]], paste0(prefix, name, ".csv"))
  }
  # Aggregate outputs only; patient-level predictions stay out of exported tables.
  save_tbl(data.table(
    outcome = outcome, patients = nrow(cohort), missing_outcomes = nrow(evaluation_data) - nrow(cohort),
    folds = evaluation$settings$folds, n_trees = evaluation$settings$n_trees,
    permutations = evaluation$settings$permutations, seed = evaluation$settings$seed,
    maxdepth = evaluation$settings$maxdepth, minsplit = evaluation$settings$minsplit,
    minbucket = evaluation$settings$minbucket,
    r_version = as.character(getRversion()), rpart_version = as.character(packageVersion("rpart")),
    features = paste(evaluation_features, collapse = ";"), source_table = "patient_analytic"
  ), paste0(prefix, "settings.csv"))
  print(evaluation$summary)
}
log_note("04b_model_evaluation: done")
