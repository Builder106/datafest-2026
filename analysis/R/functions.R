suppressPackageStartupMessages(library(data.table))

# Probability scores for a binary outcome; AUC uses average ranks for ties.
binary_model_metrics <- function(observed, probability) {
  if (!is.numeric(observed) || !is.numeric(probability) ||
      length(observed) == 0L || length(observed) != length(probability) ||
      anyNA(observed) || anyNA(probability) ||
      any(!observed %in% c(0, 1)) || any(!is.finite(probability)) ||
      any(probability < 0 | probability > 1)) {
    stop("Expected matching binary outcomes and finite probabilities in [0, 1].")
  }
  positives <- sum(observed == 1)
  negatives <- sum(observed == 0)
  auc <- if (positives == 0L || negatives == 0L) NA_real_ else {
    (sum(rank(probability)[observed == 1]) - positives * (positives + 1) / 2) /
      (positives * negatives)
  }
  clipped <- pmin(pmax(probability, 1e-15), 1 - 1e-15)
  c(auc = auc, log_loss = -mean(observed * log(clipped) +
      (1 - observed) * log1p(-clipped)), brier = mean((probability - observed)^2))
}

# Learn imputation only from training patients. All-missing columns use zero.
prepare_model_features <- function(train, test) {
  medians <- vapply(train, function(x) {
    if (all(is.na(x))) 0 else stats::median(x, na.rm = TRUE)
  }, numeric(1))
  for (j in seq_along(train)) {
    train[[j]][is.na(train[[j]])] <- medians[j]
    test[[j]][is.na(test[[j]])] <- medians[j]
  }
  list(train = train, test = test, medians = medians)
}

# Fixed, shallow probability-tree ensembles; no hyperparameter selection on test folds.
# Input is one row per patient and explicitly selected numeric predictors.
evaluate_ensemble_models <- function(data, outcome_col, feature_cols,
                                     id_col = "PatientDurableKey", folds = 5L,
                                     n_trees = 50L, permutations = 5L, seed = 2026L) {
  if (!is.data.frame(data) || anyDuplicated(names(data))) {
    stop("data must be a data.frame with unique column names.")
  }
  if (!is.character(outcome_col) || length(outcome_col) != 1L || is.na(outcome_col) ||
      !is.character(id_col) || length(id_col) != 1L || is.na(id_col) ||
      !is.character(feature_cols) || length(feature_cols) == 0L || anyNA(feature_cols) ||
      anyDuplicated(feature_cols) || outcome_col == id_col ||
      any(feature_cols %in% c(outcome_col, id_col)) ||
      !all(c(outcome_col, id_col, feature_cols) %in% names(data))) {
    stop("Select existing, distinct outcome, patient ID and numeric feature columns.")
  }
  for (parameter in c("folds", "n_trees", "permutations", "seed")) {
    value <- get(parameter)
    lower <- switch(parameter, folds = 2L, seed = 0L, 1L)
    if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
        !is.finite(value) || value < lower || value > .Machine$integer.max || value != floor(value)) {
      stop(paste(parameter, "must be a valid integer >=", lower))
    }
  }
  ids <- data[[id_col]]
  if (anyNA(ids) || anyDuplicated(ids)) stop("Patient IDs must be nonmissing and unique.")
  y <- data[[outcome_col]]
  if (!is.numeric(y) || anyNA(y) || any(!y %in% c(0, 1)) ||
      sum(y == 0) < folds || sum(y == 1) < folds) {
    stop("Outcome must be numeric 0/1 with at least folds patients in each class.")
  }
  x <- as.data.frame(data)[, feature_cols, drop = FALSE]
  if (!all(vapply(x, is.numeric, logical(1))) ||
      any(vapply(x, function(v) any(!is.finite(v) & !is.na(v)), logical(1)))) {
    stop("Features must be numeric and finite or missing.")
  }
  # Internal names keep arbitrary input names out of generated formulas.
  names(x) <- paste0("x", seq_along(x))
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    else rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  set.seed(seed)
  fold_id <- integer(length(y))
  for (class in c(0, 1)) {
    rows <- which(y == class)
    fold_id[rows] <- sample(rep(seq_len(folds), length.out = length(rows)))
  }
  predictions <- list()
  scores <- list()
  importance <- list()
  for (fold in seq_len(folds)) {
    test_rows <- which(fold_id == fold)
    train_rows <- which(fold_id != fold)
    prepared <- prepare_model_features(x[train_rows, , drop = FALSE], x[test_rows, , drop = FALSE])
    train <- prepared$train
    test <- prepared$test
    for (model in c("prevalence", "bagged_trees", "random_subspace")) {
      if (model == "prevalence") {
        probability <- rep(mean(y[train_rows]), length(test_rows))
      } else {
        trees <- lapply(seq_len(n_trees), function(i) {
          columns <- if (model == "bagged_trees") seq_along(train) else {
            sample.int(ncol(train), max(1L, floor(sqrt(ncol(train)))))
          }
          bootstrap <- sample.int(nrow(train), nrow(train), replace = TRUE)
          tree_data <- train[bootstrap, columns, drop = FALSE]
          tree_data$.outcome <- y[train_rows][bootstrap]
          rpart::rpart(.outcome ~ ., data = tree_data, method = "anova",
                       control = rpart::rpart.control(maxdepth = 3L, minsplit = 20L,
                         minbucket = 7L, cp = 0, xval = 0L, maxsurrogate = 0L))
        })
        predict_ensemble <- function(newdata) {
          Reduce(`+`, lapply(trees, function(tree) as.numeric(stats::predict(tree, newdata)))) / n_trees
        }
        probability <- predict_ensemble(test)
        loss <- binary_model_metrics(y[test_rows], probability)[["log_loss"]]
        for (j in seq_along(feature_cols)) {
          for (repeat_id in seq_len(permutations)) {
            shuffled <- test
            shuffled[[j]] <- shuffled[[j]][sample.int(nrow(test))]
            delta <- binary_model_metrics(y[test_rows], predict_ensemble(shuffled))[["log_loss"]] - loss
            importance[[length(importance) + 1L]] <- data.table(
              fold = fold, model = model, feature = feature_cols[j],
              permutation = repeat_id, log_loss_increase = delta)
          }
        }
      }
      predictions[[length(predictions) + 1L]] <- data.table(
        patient_id = ids[test_rows], row_id = test_rows, fold = fold,
        model = model, observed = y[test_rows], probability = probability)
      metric <- binary_model_metrics(y[test_rows], probability)
      scores[[length(scores) + 1L]] <- data.table(
        fold = fold, model = model, n_train = length(train_rows), n_test = length(test_rows),
        auc = metric[["auc"]], log_loss = metric[["log_loss"]], brier = metric[["brier"]])
    }
  }
  scores <- rbindlist(scores)
  importance <- rbindlist(importance)
  list(
    predictions = rbindlist(predictions),
    fold_metrics = scores,
    summary = scores[, .(folds = .N, auc_mean = mean(auc), auc_sd = sd(auc),
      log_loss_mean = mean(log_loss), log_loss_sd = sd(log_loss),
      brier_mean = mean(brier), brier_sd = sd(brier)), by = model],
    permutation_importance = importance,
    feature_importance = importance[, .(log_loss_increase_mean = mean(log_loss_increase),
      log_loss_increase_sd = sd(log_loss_increase)), by = .(model, feature)],
    settings = list(features = feature_cols, folds = folds, n_trees = n_trees,
      permutations = permutations, seed = seed, maxdepth = 3L, minsplit = 20L, minbucket = 7L)
  )
}

# Extract odds ratios and 95% Wald CI from a fitted binomial GLM.
# Returns a data.table with one row per coefficient.
coef_or <- function(m, label) {
  co <- summary(m)$coefficients
  out <- data.table(
    term = rownames(co),
    est  = co[, "Estimate"],
    se   = co[, "Std. Error"],
    z    = co[, "z value"],
    p    = co[, "Pr(>|z|)"]
  )
  out[, odds_ratio := exp(est)]
  out[, or_lo      := exp(est - 1.96 * se)]
  out[, or_hi      := exp(est + 1.96 * se)]
  out[, model      := label]
  out[]
}

# Calculate statistical mode of a vector.
calc_mode <- function(x, na.rm = TRUE) {
  if (na.rm) {
    x <- x[!is.na(x)]
  }
  if (length(x) == 0L) {
    if (is.numeric(x)) return(as.numeric(NA))
    return(as.character(NA))
  }
  tab <- table(x)
  mod_val <- names(tab)[which.max(tab)]
  if (is.numeric(x)) {
    return(as.numeric(mod_val))
  }
  if (is.factor(x)) {
    return(factor(mod_val, levels = levels(x)))
  }
  mod_val
}

# Calculate robust lower and upper outlier bounds using IQR or MAD (Hampel filter).
calc_outlier_bounds <- function(x, method = c("iqr", "mad"), threshold = NULL) {
  method <- match.arg(method)
  vals <- x[!is.na(x)]
  if (length(vals) == 0L) {
    return(list(lower = -Inf, upper = Inf))
  }
  if (method == "iqr") {
    k <- if (is.null(threshold)) 1.5 else threshold
    qs <- quantile(vals, probs = c(0.25, 0.75), names = FALSE)
    iqr_val <- qs[2L] - qs[1L]
    list(lower = qs[1L] - k * iqr_val, upper = qs[2L] + k * iqr_val)
  } else {
    k <- if (is.null(threshold)) 3.0 else threshold
    med <- median(vals)
    mad_val <- median(abs(vals - med))
    scale <- 1.4826 * mad_val
    if (scale == 0) {
      scale <- 1.2533 * mean(abs(vals - med))
    }
    if (scale == 0) {
      return(list(lower = med, upper = med))
    }
    list(lower = med - k * scale, upper = med + k * scale)
  }
}

# Return logical vector flagging outlier observations.
detect_outliers <- function(x, method = c("iqr", "mad"), threshold = NULL) {
  b <- calc_outlier_bounds(x, method = method, threshold = threshold)
  is_out <- (x < b$lower | x > b$upper)
  is_out[is.na(is_out)] <- FALSE
  is_out
}

# Winsorize / cap values exceeding lower and upper outlier boundaries.
cap_outliers <- function(x, method = c("iqr", "mad"), threshold = NULL, bounds = NULL) {
  b <- if (!is.null(bounds)) bounds else calc_outlier_bounds(x, method = method, threshold = threshold)
  out <- x
  out[!is.na(out) & out < b$lower] <- b$lower
  out[!is.na(out) & out > b$upper] <- b$upper
  out
}

# Treat outliers across specified columns in a data.table (cap or flag).
treat_outliers_dt <- function(dt, cols, method = c("iqr", "mad"), threshold = NULL, action = c("cap", "flag"), in_place = FALSE) {
  method <- match.arg(method)
  action <- match.arg(action)
  res <- if (in_place) dt else copy(dt)
  if (!is.data.table(res)) res <- as.data.table(res)
  for (col in cols) {
    if (!col %in% names(res)) next
    if (action == "cap") {
      set(res, j = col, value = cap_outliers(res[[col]], method = method, threshold = threshold))
    } else {
      flag_col <- paste0(col, "_outlier")
      set(res, j = flag_col, value = as.integer(detect_outliers(res[[col]], method = method, threshold = threshold)))
    }
  }
  res[]
}

# Robust missing value imputation for a single vector.
impute_missing <- function(x, method = c("median", "mode", "mean", "constant"), const_val = NULL, add_indicator = FALSE) {
  method <- match.arg(method)
  is_missing <- is.na(x)
  if (!any(is_missing)) {
    if (add_indicator) {
      return(list(imputed = x, indicator = integer(length(x))))
    }
    return(x)
  }
  fill <- switch(
    method,
    median   = median(x, na.rm = TRUE),
    mean     = mean(x, na.rm = TRUE),
    mode     = calc_mode(x, na.rm = TRUE),
    constant = {
      if (is.null(const_val)) stop("const_val must be provided when method = 'constant'")
      const_val
    }
  )
  out <- x
  if (is.factor(out) && !is.na(fill) && !as.character(fill) %in% levels(out)) {
    levels(out) <- c(levels(out), as.character(fill))
  }
  out[is_missing] <- fill
  if (add_indicator) {
    list(imputed = out, indicator = as.integer(is_missing))
  } else {
    out
  }
}

# Automated missing value imputation across columns of a data.table.
impute_dt <- function(dt, cols = NULL, numeric_method = "median", categorical_method = "mode", add_indicators = TRUE, in_place = FALSE) {
  res <- if (in_place) dt else copy(dt)
  if (!is.data.table(res)) res <- as.data.table(res)
  if (is.null(cols)) {
    cols <- names(res)[vapply(res, anyNA, logical(1))]
  }
  for (col in cols) {
    if (!col %in% names(res)) next
    vals <- res[[col]]
    if (!anyNA(vals)) next
    is_num <- is.numeric(vals)
    method <- if (is_num) numeric_method else categorical_method
    imp_res <- impute_missing(vals, method = method, add_indicator = add_indicators)
    if (add_indicators) {
      set(res, j = col, value = imp_res$imputed)
      ind_col <- paste0(col, "_na")
      set(res, j = ind_col, value = imp_res$indicator)
    } else {
      set(res, j = col, value = imp_res)
    }
  }
  res[]
}

# End-to-end automated cleaning pipeline: robust outlier capping and missing data imputation.
clean_pipeline_features <- function(
  dt,
  numeric_cols = NULL,
  categorical_cols = NULL,
  impute_numeric = "median",
  impute_categorical = "mode",
  outlier_method = "iqr",
  outlier_threshold = 1.5,
  outlier_action = "cap",
  add_indicators = TRUE,
  in_place = FALSE
) {
  res <- if (in_place) dt else copy(dt)
  if (!is.data.table(res)) res <- as.data.table(res)

  if (is.null(numeric_cols)) {
    all_num <- names(res)[vapply(res, is.numeric, logical(1))]
    numeric_cols <- setdiff(all_num, c("PatientDurableKey", "EncounterKey", "DepartmentKey", "ProviderDurableKey"))
  }

  if (is.null(categorical_cols)) {
    all_cat <- names(res)[vapply(res, function(col) is.character(col) || is.factor(col), logical(1))]
    categorical_cols <- setdiff(all_cat, c("PatientDurableKey", "FipsCode"))
  }

  if (length(numeric_cols) > 0L && !is.null(outlier_action)) {
    res <- treat_outliers_dt(
      res,
      cols = numeric_cols,
      method = outlier_method,
      threshold = outlier_threshold,
      action = outlier_action,
      in_place = TRUE
    )
  }

  cols_to_impute <- union(numeric_cols, categorical_cols)
  if (length(cols_to_impute) > 0L) {
    res <- impute_dt(
      res,
      cols = cols_to_impute,
      numeric_method = impute_numeric,
      categorical_method = impute_categorical,
      add_indicators = add_indicators,
      in_place = TRUE
    )
  }

  res[]
}

# Summary table comparing missingness and outlier counts before and after cleaning.
summarize_cleaning <- function(dt_raw, dt_clean, cols = NULL) {
  if (!is.data.table(dt_raw)) dt_raw <- as.data.table(dt_raw)
  if (!is.data.table(dt_clean)) dt_clean <- as.data.table(dt_clean)

  if (is.null(cols)) {
    cols <- intersect(names(dt_raw), names(dt_clean))
    cols <- setdiff(cols, c("PatientDurableKey", "EncounterKey"))
  }

  rows <- lapply(cols, function(col) {
    v_raw <- dt_raw[[col]]
    v_clean <- dt_clean[[col]]
    n_total <- length(v_raw)
    n_na_raw <- sum(is.na(v_raw))
    n_na_clean <- sum(is.na(v_clean))
    is_num <- is.numeric(v_raw)

    n_outliers <- 0L
    if (is_num) {
      flag_col <- paste0(col, "_outlier")
      if (flag_col %in% names(dt_clean)) {
        n_outliers <- sum(dt_clean[[flag_col]] == 1L, na.rm = TRUE)
      } else {
        non_na <- !is.na(v_raw)
        n_outliers <- sum(non_na & (v_raw != v_clean))
      }
    }

    data.table(
      column = col,
      type = if (is_num) "numeric" else "categorical",
      total_rows = n_total,
      missing_before = n_na_raw,
      pct_missing_before = round(100 * n_na_raw / max(1, n_total), 2),
      missing_after = n_na_clean,
      outliers_treated = n_outliers,
      pct_outliers_treated = round(100 * n_outliers / max(1, n_total - n_na_raw), 2)
    )
  })
  rbindlist(rows)
}

# Calculate pairwise correlation matrix and significance p-values for numeric features.
calc_correlation_matrix <- function(data, cols = NULL, method = c("pearson", "spearman"), use = "pairwise.complete.obs") {
  method <- match.arg(method)
  if (!is.data.frame(data)) stop("data must be a data.frame or data.table")
  dt <- as.data.table(data)
  if (is.null(cols)) {
    all_num <- names(dt)[vapply(dt, is.numeric, logical(1))]
    cols <- setdiff(all_num, c("PatientDurableKey", "EncounterKey", "DepartmentKey", "ProviderDurableKey"))
  }
  if (length(cols) < 2L) {
    stop("At least 2 numeric columns required for correlation matrix")
  }
  mat <- as.matrix(dt[, ..cols])
  col_sds <- apply(mat, 2, sd, na.rm = TRUE)
  valid_cols <- names(col_sds)[!is.na(col_sds) & col_sds > 0]
  if (length(valid_cols) < 2L) {
    stop("Fewer than 2 columns have non-zero variance")
  }
  mat <- mat[, valid_cols, drop = FALSE]
  p <- ncol(mat)
  cor_mat <- cor(mat, method = method, use = use)

  p_mat <- matrix(0, nrow = p, ncol = p, dimnames = list(valid_cols, valid_cols))
  n_mat <- matrix(0L, nrow = p, ncol = p, dimnames = list(valid_cols, valid_cols))

  pairs_list <- vector("list", p * (p - 1L) / 2L)
  idx <- 1L
  for (i in seq_len(p - 1L)) {
    for (j in seq(i + 1L, p)) {
      v1 <- mat[, i]
      v2 <- mat[, j]
      ok <- !is.na(v1) & !is.na(v2)
      n_ij <- sum(ok)
      n_mat[i, j] <- n_mat[j, i] <- n_ij
      r <- cor_mat[i, j]
      if (is.na(r) || n_ij <= 2L) {
        pval <- NA_real_
      } else if (abs(r) >= 1) {
        pval <- 0.0
      } else {
        t_stat <- r * sqrt((n_ij - 2) / (1 - r^2))
        pval <- 2 * pt(-abs(t_stat), df = n_ij - 2)
      }
      p_mat[i, j] <- p_mat[j, i] <- pval
      pairs_list[[idx]] <- data.table(
        var1 = valid_cols[i],
        var2 = valid_cols[j],
        correlation = r,
        p_value = pval,
        abs_correlation = if (is.na(r)) NA_real_ else abs(r),
        n_obs = n_ij
      )
      idx <- idx + 1L
    }
  }
  diag(n_mat) <- apply(mat, 2, function(x) sum(!is.na(x)))
  cor_dt <- rbindlist(pairs_list)
  setorder(cor_dt, -abs_correlation, na.last = TRUE)

  list(
    cor_matrix = cor_mat,
    p_matrix = p_mat,
    n_obs = n_mat,
    cor_dt = cor_dt,
    method = method,
    features = valid_cols
  )
}

# Calculate correlation of numeric features against a target outcome.
calc_feature_correlations <- function(data, target_col, feature_cols = NULL, method = c("pearson", "spearman"), use = "pairwise.complete.obs") {
  method <- match.arg(method)
  if (!is.data.frame(data)) stop("data must be a data.frame or data.table")
  dt <- as.data.table(data)
  if (!target_col %in% names(dt)) stop("target_col not found in data")
  target_vals <- dt[[target_col]]
  if (!is.numeric(target_vals)) stop("target_col must be numeric")
  if (is.null(feature_cols)) {
    all_num <- names(dt)[vapply(dt, is.numeric, logical(1))]
    feature_cols <- setdiff(all_num, c(target_col, "PatientDurableKey", "EncounterKey", "DepartmentKey", "ProviderDurableKey"))
  }
  if (length(feature_cols) == 0L) stop("No numeric feature columns found")

  rows <- lapply(feature_cols, function(col) {
    if (!col %in% names(dt)) return(NULL)
    v <- dt[[col]]
    if (!is.numeric(v)) return(NULL)
    ok <- !is.na(target_vals) & !is.na(v)
    n_ij <- sum(ok)
    if (n_ij <= 2L || sd(target_vals[ok]) == 0 || sd(v[ok]) == 0) {
      r <- NA_real_
      pval <- NA_real_
    } else {
      r <- cor(target_vals[ok], v[ok], method = method)
      if (abs(r) >= 1) {
        pval <- 0.0
      } else {
        t_stat <- r * sqrt((n_ij - 2) / (1 - r^2))
        pval <- 2 * pt(-abs(t_stat), df = n_ij - 2)
      }
    }
    data.table(
      feature = col,
      target = target_col,
      correlation = r,
      p_value = pval,
      abs_correlation = if (is.na(r)) NA_real_ else abs(r),
      n_obs = n_ij
    )
  })
  res_dt <- rbindlist(rows)
  setorder(res_dt, -abs_correlation, na.last = TRUE)
  res_dt[]
}

# Rank and extract top pairwise correlations.
find_top_correlations <- function(cor_res, top_n = 20L, min_abs_cor = 0.0) {
  cor_dt <- if (is.list(cor_res) && "cor_dt" %in% names(cor_res)) cor_res$cor_dt else cor_res
  if (!is.data.table(cor_dt)) cor_dt <- as.data.table(cor_dt)
  filtered <- cor_dt[!is.na(abs_correlation) & abs_correlation >= min_abs_cor]
  setorder(filtered, -abs_correlation)
  head(filtered, top_n)
}

# Fit Principal Component Analysis (PCA) with variance decomposition and loadings.
fit_pca <- function(data, cols = NULL, scale = TRUE, center = TRUE, n_components = NULL) {
  if (!is.data.frame(data)) stop("data must be a data.frame or data.table")
  dt <- as.data.table(data)
  if (is.null(cols)) {
    all_num <- names(dt)[vapply(dt, is.numeric, logical(1))]
    cols <- setdiff(all_num, c("PatientDurableKey", "EncounterKey", "DepartmentKey", "ProviderDurableKey"))
  }
  if (length(cols) < 2L) stop("At least 2 numeric feature columns required for PCA")
  mat <- as.matrix(dt[, ..cols])
  if (anyNA(mat)) {
    stop("Input matrix contains NA values; impute missing values before running fit_pca")
  }
  col_sds <- apply(mat, 2, sd)
  valid_cols <- names(col_sds)[col_sds > 1e-12]
  if (length(valid_cols) < 2L) {
    stop("Fewer than 2 columns have non-zero variance")
  }
  mat <- mat[, valid_cols, drop = FALSE]

  pca_res <- stats::prcomp(mat, center = center, scale. = scale)
  max_k <- min(ncol(mat), nrow(mat))
  k <- if (!is.null(n_components)) min(n_components, max_k) else max_k

  sdev_k <- pca_res$sdev[seq_len(k)]
  var_k <- sdev_k^2
  total_var <- sum(pca_res$sdev^2)
  prop_var <- var_k / total_var
  cum_var <- cumsum(prop_var)

  var_dt <- data.table(
    PC = paste0("PC", seq_len(k)),
    sdev = round(sdev_k, 5),
    variance = round(var_k, 5),
    prop_variance = round(prop_var, 5),
    cum_variance = round(cum_var, 5)
  )

  rot_mat <- pca_res$rotation[, seq_len(k), drop = FALSE]
  loadings_dt <- as.data.table(rot_mat, keep.rownames = "feature")

  scores_mat <- pca_res$x[, seq_len(k), drop = FALSE]
  scores_dt <- as.data.table(scores_mat)

  list(
    variance_explained = var_dt,
    loadings = loadings_dt,
    scores = scores_dt,
    rotation = rot_mat,
    center = pca_res$center,
    scale = pca_res$scale,
    features = valid_cols,
    n_components = k,
    prcomp_obj = pca_res
  )
}

# Project new observations onto a fitted PCA subspace.
project_pca <- function(pca_model, newdata) {
  if (!is.list(pca_model) || !all(c("rotation", "features") %in% names(pca_model))) {
    stop("pca_model must be a fitted PCA object from fit_pca")
  }
  dt <- as.data.table(newdata)
  feats <- pca_model$features
  missing_feats <- setdiff(feats, names(dt))
  if (length(missing_feats) > 0L) {
    stop(paste("New data is missing features:", paste(missing_feats, collapse = ", ")))
  }
  mat <- as.matrix(dt[, ..feats])
  if (anyNA(mat)) {
    stop("newdata contains NA values; impute missing values before projecting")
  }
  if (!is.null(pca_model$center) && is.numeric(pca_model$center)) {
    mat <- sweep(mat, 2, pca_model$center[feats], "-")
  }
  if (!is.null(pca_model$scale) && is.numeric(pca_model$scale)) {
    mat <- sweep(mat, 2, pca_model$scale[feats], "/")
  }
  proj <- mat %*% pca_model$rotation
  as.data.table(proj)
}

# Fit Uniform Manifold Approximation and Projection (UMAP) dimensional reduction.
fit_umap <- function(
  data,
  cols = NULL,
  n_components = 2L,
  n_neighbors = 15L,
  min_dist = 0.1,
  n_epochs = 100L,
  learning_rate = 1.0,
  scale = TRUE,
  seed = NULL
) {
  if (!is.null(seed)) set.seed(seed)
  if (!is.data.frame(data)) stop("data must be a data.frame or data.table")
  dt <- as.data.table(data)
  if (is.null(cols)) {
    all_num <- names(dt)[vapply(dt, is.numeric, logical(1))]
    cols <- setdiff(all_num, c("PatientDurableKey", "EncounterKey", "DepartmentKey", "ProviderDurableKey"))
  }
  if (length(cols) < 2L) stop("At least 2 numeric feature columns required for UMAP")
  mat <- as.matrix(dt[, ..cols])
  if (anyNA(mat)) stop("Input matrix contains NA values; impute missing values before running fit_umap")

  col_sds <- apply(mat, 2, sd)
  valid_cols <- names(col_sds)[col_sds > 1e-12]
  if (length(valid_cols) < 2L) stop("Fewer than 2 columns have non-zero variance")
  mat <- mat[, valid_cols, drop = FALSE]

  N <- nrow(mat)
  if (N < 3L) stop("At least 3 observations required for UMAP")

  if (scale) {
    mat <- scale(mat)
  }

  k <- max(2L, min(as.integer(n_neighbors), N - 1L))
  d_mat <- as.matrix(stats::dist(mat))
  diag(d_mat) <- 0

  target <- log2(k)
  P <- matrix(0, nrow = N, ncol = N)
  for (i in seq_len(N)) {
    d_i <- d_mat[i, ]
    d_no_self <- d_i[-i]
    rho_i <- min(d_no_self)

    lo <- 1e-5
    hi <- 1000.0
    sig_i <- 1.0
    for (iter in seq_len(32L)) {
      diffs <- pmax(0, d_no_self - rho_i)
      val <- sum(exp(-diffs / sig_i))
      if (abs(val - target) < 1e-3) break
      if (val > target) {
        hi <- sig_i
        sig_i <- (lo + hi) / 2
      } else {
        lo <- sig_i
        sig_i <- if (hi >= 1000.0) sig_i * 2 else (lo + hi) / 2
      }
    }
    p_i <- exp(-pmax(0, d_i - rho_i) / sig_i)
    p_i[i] <- 0
    P[i, ] <- p_i
  }

  P_sym <- P + t(P) - P * t(P)
  diag(P_sym) <- 0

  pca_try <- tryCatch({
    p_res <- stats::prcomp(mat, center = FALSE, scale. = FALSE)
    p_res$x[, seq_len(min(n_components, ncol(p_res$x))), drop = FALSE]
  }, error = function(e) NULL)

  if (!is.null(pca_try) && ncol(pca_try) >= n_components) {
    Y <- scale(pca_try[, seq_len(n_components), drop = FALSE]) * 0.1
  } else {
    Y <- matrix(rnorm(N * n_components, sd = 0.1), nrow = N, ncol = n_components)
  }

  n_neg <- min(5L, N - 1L)
  for (epoch in seq_len(n_epochs)) {
    alpha <- learning_rate * (1 - (epoch - 1L) / n_epochs)
    for (i in seq_len(N)) {
      diff_Y <- sweep(-Y, 2, -Y[i, ], "+")
      d2 <- rowSums(diff_Y^2)
      attr_coef <- P_sym[i, ] * 2 / (1 + d2)
      grad_attr <- colSums(attr_coef * diff_Y)
      neg_idx <- sample(setdiff(seq_len(N), i), n_neg)
      rep_coef <- 2 / ((0.001 + d2[neg_idx]) * (1 + d2[neg_idx]))
      grad_rep <- colSums(rep_coef * diff_Y[neg_idx, , drop = FALSE])

      step <- alpha * (grad_attr - 0.1 * grad_rep)
      step <- pmax(pmin(step, 4.0), -4.0)
      Y[i, ] <- Y[i, ] - step
    }
  }

  colnames(Y) <- paste0("UMAP", seq_len(n_components))
  emb_dt <- as.data.table(Y)

  list(
    embedding = emb_dt,
    n_components = n_components,
    n_neighbors = k,
    n_epochs = n_epochs,
    min_dist = min_dist,
    features = valid_cols
  )
}

