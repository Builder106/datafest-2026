library(testthat)
library(data.table)

func_path <- if (file.exists(file.path("..", "R", "functions.R"))) {
  file.path("..", "R", "functions.R")
} else {
  file.path("analysis", "R", "functions.R")
}
source(func_path)

test_that("calc_mode handles various data types and edge cases", {
  # Numeric
  expect_equal(calc_mode(c(1, 2, 2, 3, NA), na.rm = TRUE), 2)
  expect_equal(calc_mode(c(5, 5, 10)), 5)

  # Character
  expect_equal(calc_mode(c("cat", "dog", "cat", NA)), "cat")

  # Factor
  f <- factor(c("high", "low", "high", "medium"), levels = c("low", "medium", "high"))
  m_f <- calc_mode(f)
  expect_s3_class(m_f, "factor")
  expect_equal(as.character(m_f), "high")
  expect_equal(levels(m_f), c("low", "medium", "high"))

  # Empty vectors
  expect_true(is.na(calc_mode(numeric(0))))
  expect_true(is.na(calc_mode(character(0))))

  # na.rm = FALSE
  val_no_narm <- calc_mode(c(1, 1, 2), na.rm = FALSE)
  expect_equal(val_no_narm, 1)
})

test_that("calc_outlier_bounds computes correct IQR and MAD thresholds", {
  # Empty vector
  b_empty <- calc_outlier_bounds(numeric(0))
  expect_equal(b_empty$lower, -Inf)
  expect_equal(b_empty$upper, Inf)

  # IQR method default threshold (1.5)
  x <- c(10, 12, 14, 15, 16, 18, 20)
  b_iqr <- calc_outlier_bounds(x, method = "iqr")
  expect_true(b_iqr$lower < min(x))
  expect_true(b_iqr$upper > max(x))

  # IQR method custom threshold (3.0)
  b_iqr_k3 <- calc_outlier_bounds(x, method = "iqr", threshold = 3.0)
  expect_true(b_iqr_k3$lower < b_iqr$lower)
  expect_true(b_iqr_k3$upper > b_iqr$upper)

  # MAD method default threshold (3.0)
  b_mad <- calc_outlier_bounds(x, method = "mad")
  expect_true(b_mad$lower < min(x))
  expect_true(b_mad$upper > max(x))

  # MAD method custom threshold (2.0)
  b_mad_k2 <- calc_outlier_bounds(x, method = "mad", threshold = 2.0)
  expect_true(b_mad_k2$lower > b_mad$lower)

  # MAD method with >50% identical values triggering mean abs deviation fallback
  x_ties <- c(1, 1, 1, 1, 5, 8)
  b_ties <- calc_outlier_bounds(x_ties, method = "mad")
  expect_true(b_ties$upper > 1)

  # MAD method with all identical values
  x_same <- rep(10, 6)
  b_same <- calc_outlier_bounds(x_same, method = "mad")
  expect_equal(b_same$lower, 10)
  expect_equal(b_same$upper, 10)
})

test_that("detect_outliers and cap_outliers operate correctly", {
  vals <- c(10, 11, 12, 11, 10, 12, 100, -50, NA)
  out_iqr <- detect_outliers(vals, method = "iqr")

  expect_false(out_iqr[1]) # 10 is inlier
  expect_true(out_iqr[7])  # 100 is outlier
  expect_true(out_iqr[8])  # -50 is outlier
  expect_false(out_iqr[9]) # NA is not flagged

  out_mad <- detect_outliers(vals, method = "mad")
  expect_true(out_mad[7])

  # cap_outliers
  capped <- cap_outliers(vals, method = "iqr")
  expect_true(capped[7] < 100)
  expect_true(capped[8] > -50)
  expect_true(is.na(capped[9]))

  # cap_outliers with explicit bounds provided
  capped_custom <- cap_outliers(vals, bounds = list(lower = 5, upper = 25))
  expect_equal(capped_custom[7], 25)
  expect_equal(capped_custom[8], 5)
  expect_equal(capped_custom[1], 10)
})

test_that("treat_outliers_dt handles capping, flagging, and edge cases", {
  dt <- data.table(
    id = 1:6,
    val = c(10, 12, 11, 13, 90, 12)
  )

  # Flagging
  dt_flag <- treat_outliers_dt(dt, cols = c("val", "non_existent"), action = "flag", in_place = FALSE)
  expect_true("val_outlier" %in% names(dt_flag))
  expect_equal(dt_flag$val_outlier[5], 1L)
  expect_equal(dt_flag$val_outlier[1], 0L)
  expect_false("val_outlier" %in% names(dt)) # dt unmodified

  # Capping in place
  dt_copy <- copy(dt)
  dt_capped <- treat_outliers_dt(dt_copy, cols = "val", action = "cap", in_place = TRUE)
  expect_true(dt_capped$val[5] < 90)
  expect_equal(dt_copy$val[5], dt_capped$val[5]) # modified in place

  # Data.frame input converted to data.table
  df <- data.frame(id = 1:4, val = c(1, 2, 2, 50))
  df_res <- treat_outliers_dt(df, cols = "val", action = "cap")
  expect_s3_class(df_res, "data.table")
  expect_true(df_res$val[4] < 50)
})

test_that("impute_missing handles all methods, factor levels, and indicator flags", {
  # No missing values
  x_clean <- c(1, 2, 3)
  expect_equal(impute_missing(x_clean), x_clean)
  res_clean_ind <- impute_missing(x_clean, add_indicator = TRUE)
  expect_equal(res_clean_ind$imputed, x_clean)
  expect_equal(res_clean_ind$indicator, c(0L, 0L, 0L))

  # Numeric median & mean
  x_na <- c(10, 20, 30, 40, NA)
  expect_equal(impute_missing(x_na, method = "median"), c(10, 20, 30, 40, 25))
  expect_equal(impute_missing(x_na, method = "mean"), c(10, 20, 30, 40, 25))

  # Mode
  cat_na <- c("apple", "banana", "apple", NA)
  expect_equal(impute_missing(cat_na, method = "mode"), c("apple", "banana", "apple", "apple"))

  # Constant
  expect_equal(impute_missing(cat_na, method = "constant", const_val = "missing"),
               c("apple", "banana", "apple", "missing"))
  expect_error(impute_missing(cat_na, method = "constant", const_val = NULL))

  # Factor with new level
  f <- factor(c("A", "B", NA), levels = c("A", "B"))
  f_imp <- impute_missing(f, method = "constant", const_val = "C")
  expect_true("C" %in% levels(f_imp))
  expect_equal(as.character(f_imp[3]), "C")

  # Indicator flag
  res_ind <- impute_missing(x_na, method = "median", add_indicator = TRUE)
  expect_equal(res_ind$indicator, c(0L, 0L, 0L, 0L, 1L))
})

test_that("impute_dt automates imputation across data.table columns", {
  dt <- data.table(
    id = 1:5,
    num_col = c(10, 20, NA, 40, 50),
    cat_col = c("yes", "no", "yes", NA, "yes"),
    clean_col = c(1, 2, 3, 4, 5)
  )

  # Auto-detection of cols with add_indicators
  dt_imp <- impute_dt(dt, add_indicators = TRUE, in_place = FALSE)
  expect_false(anyNA(dt_imp$num_col))
  expect_false(anyNA(dt_imp$cat_col))
  expect_true("num_col_na" %in% names(dt_imp))
  expect_true("cat_col_na" %in% names(dt_imp))
  expect_equal(dt_imp$num_col[3], 30) # median of 10, 20, 40, 50
  expect_equal(dt_imp$cat_col[4], "yes") # mode
  expect_equal(dt_imp$num_col_na, c(0L, 0L, 1L, 0L, 0L))

  # Explicit cols without indicators in place
  dt_copy <- copy(dt)
  dt_explicit <- impute_dt(dt_copy, cols = c("num_col", "clean_col", "missing_col"),
                           add_indicators = FALSE, in_place = TRUE)
  expect_false(anyNA(dt_copy$num_col))
  expect_false("num_col_na" %in% names(dt_copy))

  # Data.frame input
  df <- data.frame(a = c(1, NA, 3))
  df_res <- impute_dt(df)
  expect_s3_class(df_res, "data.table")
  expect_false(anyNA(df_res$a))
})

test_that("clean_pipeline_features executes end-to-end cleaning pipeline", {
  dt <- data.table(
    PatientDurableKey = 1:8,
    age_proxy = c(20, 25, 30, 35, 40, 150, 45, NA),
    n_encounters = c(1, 2, 2, 3, 2, 200, 1, NA),
    SexAtBirth = c("Male", "Female", "Female", NA, "Male", "Female", "Female", "Female"),
    FipsCode = c("20177", "20177", NA, "20177", "20177", "20177", "20177", "20177")
  )

  # Default auto-detection
  dt_cleaned <- clean_pipeline_features(dt, in_place = FALSE)

  # ID and FipsCode should not be modified/imputed
  expect_true("PatientDurableKey" %in% names(dt_cleaned))
  expect_true(anyNA(dt_cleaned$FipsCode))

  # age_proxy and n_encounters capped and imputed
  expect_false(anyNA(dt_cleaned$age_proxy))
  expect_false(anyNA(dt_cleaned$n_encounters))
  expect_true(dt_cleaned$age_proxy[6] < 150) # outlier capped
  expect_true(dt_cleaned$n_encounters[6] < 200) # outlier capped
  expect_true("age_proxy_na" %in% names(dt_cleaned))

  # SexAtBirth imputed with mode
  expect_false(anyNA(dt_cleaned$SexAtBirth))
  expect_equal(dt_cleaned$SexAtBirth[4], "Female")

  # Custom parameters with outlier_action = NULL
  dt_no_outlier <- clean_pipeline_features(
    dt,
    numeric_cols = "age_proxy",
    categorical_cols = "SexAtBirth",
    outlier_action = NULL,
    add_indicators = FALSE
  )
  expect_equal(dt_no_outlier$age_proxy[6], 150) # not capped
  expect_false("age_proxy_na" %in% names(dt_no_outlier))

  # Data.frame input with in_place = TRUE
  df <- data.frame(PatientDurableKey = 1:3, x = c(1, NA, 3))
  df_cleaned <- clean_pipeline_features(df, in_place = TRUE)
  expect_s3_class(df_cleaned, "data.table")
  expect_false(anyNA(df_cleaned$x))
})

test_that("summarize_cleaning generates comprehensive audit metrics", {
  dt_raw <- data.table(
    PatientDurableKey = 1:6,
    age = c(20, 25, 30, 35, 120, NA),
    category = c("A", "B", "A", NA, "A", "B")
  )

  # Capped cleaning
  dt_clean <- clean_pipeline_features(dt_raw, in_place = FALSE)
  summary_cap <- summarize_cleaning(dt_raw, dt_clean)

  expect_s3_class(summary_cap, "data.table")
  expect_true(all(c("column", "type", "total_rows", "missing_before",
                    "missing_after", "outliers_treated") %in% names(summary_cap)))

  age_row <- summary_cap[column == "age"]
  expect_equal(age_row$missing_before, 1L)
  expect_equal(age_row$missing_after, 0L)
  expect_equal(age_row$outliers_treated, 1L)

  cat_row <- summary_cap[column == "category"]
  expect_equal(cat_row$missing_before, 1L)
  expect_equal(cat_row$missing_after, 0L)
  expect_equal(cat_row$outliers_treated, 0L)

  # Flagging cleaning
  dt_flagged <- treat_outliers_dt(dt_raw, cols = "age", action = "flag")
  dt_flagged_imp <- impute_dt(dt_flagged)
  summary_flag <- summarize_cleaning(dt_raw, dt_flagged_imp, cols = "age")
  expect_equal(summary_flag$outliers_treated, 1L)

  # Non-data.table inputs to summarize_cleaning
  df_raw <- data.frame(id = 1:3, val = c(1, NA, 3))
  df_clean <- data.frame(id = 1:3, val = c(1, 2, 3))
  s_df <- summarize_cleaning(df_raw, df_clean, cols = "val")
  expect_equal(s_df$missing_before, 1L)
})
