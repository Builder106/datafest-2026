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

log_note("03c_eda_dimred: start")

if (!file.exists(DB_PATH)) {
  log_note("03c_eda_dimred: DuckDB database not found at", DB_PATH, "(skipping database update)")
} else {
  con <- connect_db(read_only = FALSE)
  on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

  table_name <- if (dbExistsTable(con, "patient_analytic_clean")) {
    "patient_analytic_clean"
  } else if (dbExistsTable(con, "patient_analytic")) {
    "patient_analytic"
  } else {
    NULL
  }

  if (is.null(table_name)) {
    log_note("03c_eda_dimred: patient_analytic(_clean) table not found in DuckDB. (Run 03_journey.R first)")
  } else {
    log_note("reading features from DuckDB table:", table_name)
    pa_dt <- as.data.table(dbGetQuery(con, sprintf("SELECT * FROM %s;", table_name)))
    log_note("retrieved", format(nrow(pa_dt), big.mark = ","), "patient rows for EDA and dimensional reduction")

    numeric_features <- intersect(
      c("age_proxy", "block_population", "n_encounters", "days_observed",
        "n_ed", "n_inpatient", "n_hospadm", "n_obs", "n_opf2f", "n_hod",
        "n_departments", "n_providers", "n_distinct_days", "gap_median",
        "gap_mean", "gap_q25", "gap_q75", "n_gaps", "n_gap_le30",
        "n_gap_le90", "n_gap_gt180"),
      names(pa_dt)
    )

    log_note("1. Computing statistical correlation matrices (Pearson & Spearman)")
    cor_res_pearson <- calc_correlation_matrix(pa_dt, cols = numeric_features, method = "pearson")
    cor_mat_dt <- as.data.table(cor_res_pearson$cor_matrix, keep.rownames = "feature")
    save_tbl(cor_mat_dt, "eda_correlation_matrix_pearson.csv")

    p_mat_dt <- as.data.table(cor_res_pearson$p_matrix, keep.rownames = "feature")
    save_tbl(p_mat_dt, "eda_correlation_pvalues.csv")

    top_cor <- find_top_correlations(cor_res_pearson, top_n = 25L, min_abs_cor = 0.20)
    save_tbl(top_cor, "eda_top_correlations.csv")
    log_note("top collinear feature pairs identified:")
    print(head(top_cor, 10L))

    if ("n_ed" %in% names(pa_dt)) {
      log_note("computing feature correlations against acute ED visits (n_ed)")
      ed_cor <- calc_feature_correlations(pa_dt, target_col = "n_ed", feature_cols = numeric_features)
      save_tbl(ed_cor, "eda_target_correlations_ed.csv")
    }

    if ("n_inpatient" %in% names(pa_dt)) {
      log_note("computing feature correlations against inpatient admissions (n_inpatient)")
      inpat_cor <- calc_feature_correlations(pa_dt, target_col = "n_inpatient", feature_cols = numeric_features)
      save_tbl(inpat_cor, "eda_target_correlations_inpatient.csv")
    }

    log_note("2. Computing Principal Component Analysis (PCA)")
    pca_dt <- pa_dt[, ..numeric_features]
    pca_dt <- na.omit(pca_dt)
    pca_fit <- fit_pca(pca_dt, scale = TRUE, center = TRUE, n_components = 10L)

    save_tbl(pca_fit$variance_explained, "eda_pca_variance_explained.csv")
    save_tbl(pca_fit$loadings, "eda_pca_loadings.csv")
    log_note("PCA variance explained summary:")
    print(pca_fit$variance_explained)

    pca_scores <- cbind(pa_dt[seq_len(nrow(pca_fit$scores)), .(PatientDurableKey)], pca_fit$scores)
    save_tbl(head(pca_scores, 1000L), "eda_pca_scores_sample.csv")

    log_note("writing patient_analytic_pca to DuckDB")
    dbExecute(con, "DROP TABLE IF EXISTS patient_analytic_pca;")
    dbWriteTable(con, "patient_analytic_pca", pca_scores)

    log_note("3. Computing Uniform Manifold Approximation and Projection (UMAP)")
    set.seed(42)
    sample_size <- min(2000L, nrow(pa_dt))
    sample_idx <- if (nrow(pa_dt) > sample_size) sample(nrow(pa_dt), sample_size) else seq_len(nrow(pa_dt))
    umap_sample <- pa_dt[sample_idx, ..numeric_features]
    umap_sample <- na.omit(umap_sample)

    umap_fit <- fit_umap(
      data = umap_sample,
      n_components = 2L,
      n_neighbors = 15L,
      min_dist = 0.1,
      n_epochs = 100L,
      learning_rate = 1.0,
      scale = TRUE,
      seed = 42
    )

    umap_coords <- cbind(pa_dt[sample_idx[seq_len(nrow(umap_fit$embedding))], .(PatientDurableKey)], umap_fit$embedding)
    if ("transport_status" %in% names(pa_dt)) {
      umap_coords[, transport_status := pa_dt[sample_idx[seq_len(nrow(umap_fit$embedding))], transport_status]]
    }
    save_tbl(umap_coords, "eda_umap_embedding_sample.csv")

    log_note("writing patient_analytic_umap to DuckDB")
    dbExecute(con, "DROP TABLE IF EXISTS patient_analytic_umap;")
    dbWriteTable(con, "patient_analytic_umap", umap_coords)
    log_note("patient_analytic_umap created successfully with",
             format(nrow(umap_coords), big.mark = ","), "rows")
  }
}

log_note("03c_eda_dimred: done")
