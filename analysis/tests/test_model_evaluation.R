library(testthat)
library(data.table)

func_path <- if (file.exists(file.path("..", "R", "functions.R"))) {
  file.path("..", "R", "functions.R")
} else {
  file.path("analysis", "R", "functions.R")
}
source(func_path)

model_fixture <- function() {
  data.frame(PatientDurableKey = seq_len(240), outcome = rep(0:1, each = 120),
             signal = rep(0:1, each = 120), noise = rep(seq_len(120), 2))
}

test_that("binary scores match hand calculations, including ties and endpoints", {
  y <- c(0, 0, 1, 1)
  p <- c(0.1, 0.5, 0.5, 0.9)
  scores <- binary_model_metrics(y, p)
  expect_equal(scores[["auc"]], 0.875)
  expect_equal(scores[["log_loss"]], -mean(log(c(0.9, 0.5, 0.5, 0.9))))
  expect_equal(scores[["brier"]], 0.13)
  expect_equal(binary_model_metrics(c(0, 1), c(1, 0))[["auc"]], 0)
  expect_true(all(is.finite(binary_model_metrics(c(0, 1), c(0, 1)))))
  expect_true(is.na(binary_model_metrics(c(0, 0), c(0.2, 0.4))[["auc"]]))
  for (bad in list(numeric(), NA_real_, c(-0.1, 0.5), c(0.1, Inf), c(0, 1.1), c("0", "1"))) {
    expect_error(binary_model_metrics(c(0, 1), bad), "Expected matching")
  }
  expect_error(binary_model_metrics(c(0, 2), c(0.1, 0.5)), "Expected matching")
  expect_error(binary_model_metrics(c(0, NA), c(0.1, 0.5)), "Expected matching")
})

test_that("imputation learns no statistics from held-out patients", {
  train <- data.frame(age = c(10, 20, NA), absent = c(NA_real_, NA_real_, NA_real_))
  test <- data.frame(age = c(10000, NA), absent = c(99, NA))
  prepared <- prepare_model_features(train, test)
  expect_equal(prepared$medians, c(age = 15, absent = 0))
  expect_equal(prepared$train$age, c(10, 20, 15))
  expect_equal(prepared$test$age, c(10000, 15))
  expect_equal(prepared$test$absent, c(99, 0))
  expect_true(is.na(train$age[3]))
  expect_true(is.na(test$age[2]))
})

test_that("cross-validation holds out each patient once and identifies predictive features", {
  df <- model_fixture()
  result <- evaluate_ensemble_models(df, "outcome", c("signal", "noise"),
                                    folds = 3L, n_trees = 12L, permutations = 3L)
  expect_setequal(result$summary$model, c("prevalence", "bagged_trees", "random_subspace"))
  expect_equal(nrow(result$fold_metrics), 9L)
  expect_equal(nrow(result$predictions), nrow(df) * 3L)
  expect_true(all(result$predictions$probability >= 0 & result$predictions$probability <= 1))
  expect_true(all(is.finite(as.matrix(result$summary[, -"model"]))))
  expect_equal(result$settings$maxdepth, 3L)
  expect_equal(result$settings$features, c("signal", "noise"))
  expect_true(all(result$predictions[, .N, by = .(model, patient_id)]$N == 1L))
  expect_true(all(result$predictions[, uniqueN(fold), by = patient_id]$V1 == 1L))
  expect_equal(result$predictions$observed, df$outcome[result$predictions$row_id])
  for (current_fold in 1:3) {
    held_out <- result$predictions[model == "prevalence" & fold == current_fold]
    expect_equal(as.integer(table(held_out$observed)), c(40L, 40L))
    training_rows <- setdiff(seq_len(nrow(df)), held_out$row_id)
    expect_equal(held_out$probability, rep(mean(df$outcome[training_rows]), nrow(held_out)))
    for (model_name in result$summary$model) {
      pred <- result$predictions[model == model_name & fold == current_fold]
      score <- result$fold_metrics[model == model_name & fold == current_fold]
      expect_equal(score$n_train, length(training_rows))
      expect_equal(score$n_test, nrow(pred))
      expect_equal(unlist(score[, .(auc, log_loss, brier)], use.names = FALSE),
                   unname(binary_model_metrics(pred$observed, pred$probability)))
    }
  }
  expect_equal(result$summary[model == "prevalence", auc_mean], 0.5)
  expect_gt(result$summary[model == "bagged_trees", auc_mean], 0.95)
  expect_lt(result$summary[model == "bagged_trees", brier_mean],
            result$summary[model == "prevalence", brier_mean])
  expect_equal(nrow(result$permutation_importance), 3L * 2L * 2L * 3L)
  for (model_name in c("bagged_trees", "random_subspace")) {
    imp <- result$feature_importance[model == model_name]
    expect_gt(imp[feature == "signal", log_loss_increase_mean],
              imp[feature == "noise", log_loss_increase_mean])
  }
  expect_equal(result$feature_importance$log_loss_increase_mean,
    result$permutation_importance[, mean(log_loss_increase), by = .(model, feature)]$V1)
})

test_that("seeds reproduce results and preserve the caller RNG with or without prior state", {
  df <- model_fixture()
  df$signal[c(1, 140)] <- NA
  df$empty <- NA_real_
  set.seed(87)
  prior <- .Random.seed
  first <- evaluate_ensemble_models(as.data.table(df), "outcome", c("signal", "empty"),
                                   folds = 2L, n_trees = 2L, permutations = 1L, seed = 0L)
  expect_identical(.Random.seed, prior)
  second <- evaluate_ensemble_models(df, "outcome", c("signal", "empty"),
                                    folds = 2L, n_trees = 2L, permutations = 1L, seed = 0L)
  expect_equal(first, second)
  expect_true(is.na(df$signal[1]))
  rm(".Random.seed", envir = .GlobalEnv)
  on.exit(assign(".Random.seed", prior, envir = .GlobalEnv), add = TRUE)
  tiny <- data.frame(PatientDurableKey = 1:8, outcome = rep(0:1, 4), `one feature` = 1,
                     check.names = FALSE)
  constant <- evaluate_ensemble_models(tiny, "outcome", "one feature", folds = 2L,
                                       n_trees = 1L, permutations = 1L)
  expect_false(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
  expect_equal(constant$feature_importance$log_loss_increase_mean, c(0, 0))
  expect_true(all(is.finite(constant$predictions$probability)))
})

test_that("evaluation rejects invalid schemas, parameters and patient cohorts", {
  df <- model_fixture()
  evaluate <- function(data = df, ...) {
    evaluate_ensemble_models(data, "outcome", "signal", ...)
  }
  expect_error(evaluate("bad"), "data must be")
  duplicate_names <- df
  names(duplicate_names)[4] <- "signal"
  expect_error(evaluate(duplicate_names), "unique column")
  for (features in list(character(), "missing", "outcome", "PatientDurableKey",
                       c("signal", "signal"), NA_character_, 1)) {
    expect_error(evaluate_ensemble_models(df, "outcome", features), "Select existing")
  }
  expect_error(evaluate_ensemble_models(df, c("outcome", "noise"), "signal"), "Select existing")
  expect_error(evaluate_ensemble_models(df, NA_character_, "signal"), "Select existing")
  expect_error(evaluate_ensemble_models(df, "outcome", "signal", id_col = "outcome"), "Select existing")
  expect_error(evaluate_ensemble_models(df, "outcome", "signal", id_col = NULL), "Select existing")
  for (bad in list(1L, NA_real_, Inf, 2.5, "3", c(2L, 3L), numeric(), 2^32)) {
    expect_error(evaluate(folds = bad), "folds must be")
  }
  expect_error(evaluate(n_trees = 0), "n_trees must be")
  expect_error(evaluate(permutations = 0), "permutations must be")
  expect_error(evaluate(seed = -1), "seed must be")
  for (ids in list(rep(1, nrow(df)), c(NA, seq_len(nrow(df) - 1)))) {
    bad <- df
    bad$PatientDurableKey <- ids
    expect_error(evaluate(bad), "Patient IDs")
  }
  for (outcomes in list(rep(0, nrow(df)), rep(2, nrow(df)),
                        rep(NA_real_, nrow(df)), as.character(df$outcome))) {
    bad <- df
    bad$outcome <- outcomes
    expect_error(evaluate(bad), "Outcome must be")
  }
  for (signal in list(rep("a", nrow(df)), rep(Inf, nrow(df)))) {
    bad <- df
    bad$signal <- signal
    expect_error(evaluate(bad), "Features must be")
  }
})
