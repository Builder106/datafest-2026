library(testthat)
library(data.table)

source("analysis/R/functions.R")

test_that("coef_or returns expected columns and labels", {
  set.seed(42)
  x <- rbinom(400, 1, 0.3)
  y <- rbinom(400, 1, plogis(-1 + 0.9 * x))
  m <- glm(y ~ x, family = binomial())

  result <- coef_or(m, "my_model")

  expect_s3_class(result, "data.table")
  expect_true(all(c("term", "est", "se", "z", "p",
                     "odds_ratio", "or_lo", "or_hi", "model") %in% names(result)))
  expect_true(all(result$model == "my_model"))
  expect_true("(Intercept)" %in% result$term)
  expect_true("x" %in% result$term)
})

test_that("coef_or OR is positive and CI is ordered for a positive predictor", {
  set.seed(1)
  x <- rbinom(600, 1, 0.35)
  y <- rbinom(600, 1, plogis(-1 + 1.2 * x))
  m <- glm(y ~ x, family = binomial())

  result <- coef_or(m, "test")
  row <- result[term == "x"]

  expect_true(row$odds_ratio > 1)
  expect_true(row$or_lo > 0)
  expect_true(row$or_lo < row$odds_ratio)
  expect_true(row$odds_ratio < row$or_hi)
})

test_that("coef_or CI is wider for smaller samples", {
  set.seed(7)
  make_m <- function(n) {
    x <- rbinom(n, 1, 0.3)
    y <- rbinom(n, 1, plogis(-0.8 + 0.9 * x))
    glm(y ~ x, family = binomial())
  }

  small <- coef_or(make_m(60),   "small")
  large <- coef_or(make_m(6000), "large")

  ci_small <- small[term == "x", or_hi - or_lo]
  ci_large <- large[term == "x", or_hi - or_lo]
  expect_true(ci_small > ci_large)
})

test_that("coef_or preserves all terms in a multi-predictor model", {
  set.seed(99)
  x1 <- rbinom(300, 1, 0.4)
  x2 <- rnorm(300)
  y  <- rbinom(300, 1, plogis(-0.5 + 0.7 * x1 - 0.2 * x2))
  m  <- glm(y ~ x1 + x2, family = binomial())

  result <- coef_or(m, "multi")
  expect_equal(nrow(result), 3L)
  expect_true(all(c("(Intercept)", "x1", "x2") %in% result$term))
})
