library(testthat)
library(data.table)

func_path <- if (file.exists(file.path("..", "R", "functions.R"))) {
  file.path("..", "R", "functions.R")
} else {
  file.path("analysis", "R", "functions.R")
}
source(func_path)

test_that("calc_correlation_matrix computes Pearson and Spearman correlations and p-values", {
  set.seed(42)
  x1 <- rnorm(40)
  x2 <- x1 * 0.85 + rnorm(40, sd = 0.3)
  x3 <- -x1 * 0.70 + rnorm(40, sd = 0.4)
  x4 <- rnorm(40)
  df <- data.frame(
    PatientDurableKey = 1:40,
    x1 = x1,
    x2 = x2,
    x3 = x3,
    x4 = x4,
    const_col = rep(5, 40)
  )

  # Pearson with auto numeric column detection
  res_pearson <- calc_correlation_matrix(df, method = "pearson")
  expect_true(is.list(res_pearson))
  expect_equal(res_pearson$method, "pearson")
  expect_false("PatientDurableKey" %in% res_pearson$features)
  expect_false("const_col" %in% res_pearson$features)
  expect_equal(sort(res_pearson$features), c("x1", "x2", "x3", "x4"))

  # Matrix dimensions
  expect_equal(dim(res_pearson$cor_matrix), c(4L, 4L))
  expect_equal(dim(res_pearson$p_matrix), c(4L, 4L))
  expect_equal(dim(res_pearson$n_obs), c(4L, 4L))

  # Tidy table
  expect_s3_class(res_pearson$cor_dt, "data.table")
  expect_equal(nrow(res_pearson$cor_dt), 6L) # 4 choose 2
  expect_true(all(c("var1", "var2", "correlation", "p_value", "abs_correlation", "n_obs") %in% names(res_pearson$cor_dt)))
  expect_true(res_pearson$cor_dt[var1 == "x1" & var2 == "x2", correlation] > 0.8)
  expect_true(res_pearson$cor_dt[var1 == "x1" & var2 == "x2", p_value] < 0.001)

  # Spearman method and explicit cols
  res_spearman <- calc_correlation_matrix(df, cols = c("x1", "x2", "x3"), method = "spearman")
  expect_equal(res_spearman$method, "spearman")
  expect_equal(nrow(res_spearman$cor_dt), 3L)

  # Edge case: perfect correlation (|r| >= 1) yields p_value = 0
  df_perf <- data.frame(a = 1:10, b = (1:10) * 2)
  res_perf <- calc_correlation_matrix(df_perf)
  expect_equal(res_perf$cor_dt$correlation[1], 1.0)
  expect_equal(res_perf$cor_dt$p_value[1], 0.0)

  # Edge case: small sample (n <= 2) yields NA p_value
  df_small <- data.frame(a = c(1, 2), b = c(2, 4))
  res_small <- calc_correlation_matrix(df_small)
  expect_true(is.na(res_small$cor_dt$p_value[1]))

  # Error conditions
  expect_error(calc_correlation_matrix("not_a_df"), "data must be a data.frame or data.table")
  expect_error(calc_correlation_matrix(data.frame(a = 1:5)), "At least 2 numeric columns required")
  expect_error(calc_correlation_matrix(data.frame(a = rep(1, 5), b = rep(2, 5))), "Fewer than 2 columns have non-zero variance")
})

test_that("calc_feature_correlations computes target associations accurately", {
  set.seed(123)
  target <- rnorm(50)
  f_pos <- target * 0.9 + rnorm(50, sd = 0.2)
  f_neg <- -target * 0.8 + rnorm(50, sd = 0.3)
  f_rand <- rnorm(50)
  f_char <- rep("groupA", 50)
  f_const <- rep(10, 50)

  df <- data.frame(
    target = target,
    f_pos = f_pos,
    f_neg = f_neg,
    f_rand = f_rand,
    f_char = f_char,
    f_const = f_const,
    stringsAsFactors = FALSE
  )

  # Default feature detection
  res <- calc_feature_correlations(df, target_col = "target")
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 4L) # f_pos, f_neg, f_rand, f_const
  expect_equal(res$feature[1], "f_pos")
  expect_true(res$correlation[1] > 0.8)
  expect_true(res$p_value[1] < 1e-10)

  # Constant feature handling
  row_const <- res[feature == "f_const"]
  expect_true(is.na(row_const$correlation))
  expect_true(is.na(row_const$p_value))

  # Explicit feature selection including non-existent and non-numeric
  res_spec <- calc_feature_correlations(
    df,
    target_col = "target",
    feature_cols = c("f_pos", "f_char", "non_existent"),
    method = "spearman"
  )
  expect_equal(nrow(res_spec), 1L)
  expect_equal(res_spec$feature, "f_pos")

  # Perfect correlation (|r| >= 1)
  df_perf <- data.frame(y = 1:10, x = (1:10) * 3)
  res_perf <- calc_feature_correlations(df_perf, target_col = "y")
  expect_equal(res_perf$correlation[1], 1.0)
  expect_equal(res_perf$p_value[1], 0.0)

  # Small sample (n <= 2)
  df_tiny <- data.frame(y = c(1, 2), x = c(3, 4))
  res_tiny <- calc_feature_correlations(df_tiny, target_col = "y")
  expect_true(is.na(res_tiny$correlation[1]))
  expect_true(is.na(res_tiny$p_value[1]))

  # Errors
  expect_error(calc_feature_correlations("not_df", "target"), "data must be a data.frame or data.table")
  expect_error(calc_feature_correlations(df, "unknown_col"), "target_col not found in data")
  expect_error(calc_feature_correlations(df, "f_char"), "target_col must be numeric")
  expect_error(calc_feature_correlations(data.frame(target = 1:5), "target"), "No numeric feature columns found")
})

test_that("find_top_correlations filters and orders pairwise correlations", {
  cor_dt <- data.table(
    var1 = c("a", "b", "c", "d"),
    var2 = c("b", "c", "d", "e"),
    correlation = c(0.85, -0.65, 0.15, NA),
    abs_correlation = c(0.85, 0.65, 0.15, NA),
    p_value = c(0.001, 0.01, 0.4, NA)
  )

  # From data.table directly
  top <- find_top_correlations(cor_dt, top_n = 2L, min_abs_cor = 0.5)
  expect_equal(nrow(top), 2L)
  expect_equal(top$var1, c("a", "b"))

  # From calc_correlation_matrix result object
  res_obj <- list(cor_dt = cor_dt)
  top_obj <- find_top_correlations(res_obj, top_n = 1L)
  expect_equal(nrow(top_obj), 1L)
  expect_equal(top_obj$var1, "a")

  # From base data.frame
  top_df <- find_top_correlations(as.data.frame(cor_dt), top_n = 5L, min_abs_cor = 0.0)
  expect_equal(nrow(top_df), 3L) # excludes NA
})

test_that("fit_pca performs singular value decomposition and score projection", {
  set.seed(42)
  n <- 60
  z1 <- rnorm(n)
  z2 <- rnorm(n)
  x1 <- z1 + rnorm(n, sd = 0.1)
  x2 <- z1 * 0.8 + z2 * 0.2
  x3 <- z2 + rnorm(n, sd = 0.2)
  x4 <- rnorm(n)
  df <- data.frame(
    PatientDurableKey = seq_len(n),
    x1 = x1,
    x2 = x2,
    x3 = x3,
    x4 = x4,
    c_zero = rep(0, n)
  )

  # Full PCA fit
  pca_res <- fit_pca(df, scale = TRUE, center = TRUE)
  expect_true(is.list(pca_res))
  expect_equal(pca_res$n_components, 4L)
  expect_equal(nrow(pca_res$variance_explained), 4L)
  expect_equal(pca_res$variance_explained$PC, c("PC1", "PC2", "PC3", "PC4"))
  expect_equal(round(sum(pca_res$variance_explained$prop_variance), 1), 1.0)
  expect_equal(pca_res$variance_explained$cum_variance[4], 1.0)

  # Loadings and scores
  expect_equal(nrow(pca_res$loadings), 4L)
  expect_equal(ncol(pca_res$loadings), 5L) # feature + PC1..PC4
  expect_equal(nrow(pca_res$scores), n)
  expect_equal(ncol(pca_res$scores), 4L)

  # Limited components
  pca_k2 <- fit_pca(df, cols = c("x1", "x2", "x3", "x4"), n_components = 2L)
  expect_equal(pca_k2$n_components, 2L)
  expect_equal(nrow(pca_k2$variance_explained), 2L)
  expect_equal(ncol(pca_k2$scores), 2L)

  # Projection of new data
  newdata <- data.frame(x1 = c(1, 0), x2 = c(0.8, 0), x3 = c(0, 1), x4 = c(0, 0))
  proj <- project_pca(pca_res, newdata)
  expect_s3_class(proj, "data.table")
  expect_equal(nrow(proj), 2L)
  expect_equal(ncol(proj), 4L)

  # Project training data matches fitted scores
  train_proj <- project_pca(pca_res, df[, pca_res$features])
  expect_equal(unname(as.matrix(train_proj)), unname(as.matrix(pca_res$scores)), tolerance = 1e-6)

  # Error conditions
  expect_error(fit_pca("not_df"), "data must be a data.frame or data.table")
  expect_error(fit_pca(data.frame(x = 1:5)), "At least 2 numeric feature columns required")
  expect_error(fit_pca(data.frame(x = c(1, NA, 3), y = 1:3)), "Input matrix contains NA values")
  expect_error(fit_pca(data.frame(x = rep(1, 5), y = rep(2, 5))), "Fewer than 2 columns have non-zero variance")

  expect_error(project_pca("not_model", newdata), "pca_model must be a fitted PCA object from fit_pca")
  expect_error(project_pca(pca_res, data.frame(x1 = 1:2)), "New data is missing features")
  expect_error(project_pca(pca_res, data.frame(x1 = c(1, NA), x2 = 1:2, x3 = 1:2, x4 = 1:2)), "newdata contains NA values")
})

test_that("fit_umap generates manifold embeddings and handles parameters and edge cases", {
  set.seed(101)
  # 2 distinct clusters
  c1 <- matrix(rnorm(25 * 3, mean = -4), ncol = 3)
  c2 <- matrix(rnorm(25 * 3, mean = 4), ncol = 3)
  df <- as.data.frame(rbind(c1, c2))
  names(df) <- c("f1", "f2", "f3")
  df$PatientDurableKey <- seq_len(nrow(df))
  df$const_col <- rep(2, nrow(df))

  # Standard fit
  umap_res <- fit_umap(
    df,
    n_components = 2L,
    n_neighbors = 10L,
    min_dist = 0.1,
    n_epochs = 35L,
    learning_rate = 1.0,
    scale = TRUE,
    seed = 42
  )

  expect_true(is.list(umap_res))
  expect_equal(umap_res$n_components, 2L)
  expect_equal(sort(umap_res$features), c("f1", "f2", "f3"))
  expect_s3_class(umap_res$embedding, "data.table")
  expect_equal(dim(umap_res$embedding), c(50L, 2L))
  expect_equal(names(umap_res$embedding), c("UMAP1", "UMAP2"))

  # Separation verification between cluster 1 and cluster 2
  m1 <- mean(umap_res$embedding$UMAP1[1:25])
  m2 <- mean(umap_res$embedding$UMAP1[26:50])
  expect_true(abs(m1 - m2) > 5)

  # Scale = FALSE
  u_unscaled <- fit_umap(df[, c("f1", "f2", "f3")], scale = FALSE, n_epochs = 15L, seed = 7)
  expect_equal(nrow(u_unscaled$embedding), 50L)

  # Fallback to random initialization when n_components > ncol(features)
  df_2col <- data.frame(a = rnorm(15), b = rnorm(15))
  u_rand_init <- fit_umap(df_2col, n_components = 3L, n_epochs = 10L, seed = 1)
  expect_equal(ncol(u_rand_init$embedding), 3L)

  # Error conditions
  expect_error(fit_umap("not_df"), "data must be a data.frame or data.table")
  expect_error(fit_umap(data.frame(a = 1:5)), "At least 2 numeric feature columns required")
  expect_error(fit_umap(data.frame(a = c(1, NA), b = 1:2)), "Input matrix contains NA values")
  expect_error(fit_umap(data.frame(a = rep(1, 5), b = rep(2, 5))), "Fewer than 2 columns have non-zero variance")
  expect_error(fit_umap(data.frame(a = c(1, 2), b = c(2, 3))), "At least 3 observations required for UMAP")
})
