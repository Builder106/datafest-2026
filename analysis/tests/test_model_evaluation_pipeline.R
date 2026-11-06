library(testthat)
library(data.table)

test_that("model evaluation reads raw DuckDB patients and exports both outcomes", {
  repo_root <- if (file.exists(file.path("..", "R", "04b_model_evaluation.R"))) {
    normalizePath(file.path("..", ".."))
  } else {
    normalizePath(".")
  }
  fixture_dir <- tempfile("model-pipeline-")
  dir.create(fixture_dir)
  on.exit(unlink(fixture_dir, recursive = TRUE), add = TRUE)
  db_path <- file.path(fixture_dir, "fixture.duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
  patients <- data.frame(
    PatientDurableKey = 1:121, age_proxy = c(rep(c(25, 45, 65, NA), 30), 50),
    SexAtBirth = c(rep(c("Female", "Male", "Other", NA), 30), "Female"),
    transport_status = c(rep(c("barrier", "no_barrier"), 60), "not_screened"),
    n_ed = c(rep(0:1, 60), 1), n_inpatient = c(rep(c(0, 1, 1, 0), 30), 1))
  patients$n_ed[1] <- NA
  patients$n_inpatient[2] <- NA
  DBI::dbWriteTable(con, "patient_analytic", patients)
  # A cleaned table must never supply evaluation features or outcomes.
  DBI::dbWriteTable(con, "patient_analytic_clean", data.frame(invalid = 1))
  DBI::dbDisconnect(con, shutdown = TRUE)

  withr::local_envvar(c(DATAFEST_ROOT = repo_root))
  isolated <- new.env(parent = globalenv())
  # Replace only filesystem configuration; SQL, DB IO, models and exports are real.
  isolated$source <- function(file) {
    if (basename(file) == "00_config.R") {
      isolated$connect_db <- function(read_only = FALSE) {
        DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = read_only)
      }
      isolated$dbGetQuery <- DBI::dbGetQuery
      isolated$dbDisconnect <- DBI::dbDisconnect
      isolated$save_tbl <- function(x, name) fwrite(x, file.path(fixture_dir, name))
      isolated$log_note <- function(...) invisible(NULL)
    } else {
      sys.source(file, envir = isolated)
    }
  }
  capture.output(sys.source(file.path(repo_root, "analysis", "R", "04b_model_evaluation.R"),
                            envir = isolated))
  for (outcome in c("any_ed", "any_inpatient")) {
    prefix <- paste0("model_", outcome, "_")
    for (suffix in c("fold_metrics", "summary", "permutation_importance", "feature_importance", "settings")) {
      output <- fread(file.path(fixture_dir, paste0(prefix, suffix, ".csv")))
      expect_gt(nrow(output), 0L)
      expect_false(any(c("patient_id", "PatientDurableKey", "row_id") %in% names(output)))
    }
    metrics <- fread(file.path(fixture_dir, paste0(prefix, "fold_metrics.csv")))
    expect_equal(nrow(metrics), 15L)
    expect_true(all(is.finite(metrics$auc)))
    expect_equal(sum(metrics[model == "prevalence", n_test]), 119L)
    settings <- fread(file.path(fixture_dir, paste0(prefix, "settings.csv")))
    expect_equal(settings$source_table, "patient_analytic")
    expect_equal(settings$patients, 119L)
    expect_equal(settings$missing_outcomes, 1L)
    expect_equal(settings$seed, 2026L)
  }
})
