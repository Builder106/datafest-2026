suppressPackageStartupMessages(library(data.table))

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
