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
