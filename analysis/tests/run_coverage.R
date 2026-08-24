#!/usr/bin/env Rscript

script_file <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_file <- sub("^--file=", "", script_file[[1]])
script_file <- gsub("~+~", " ", script_file, fixed = TRUE)
source_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
setwd(source_root)

coverage <- covr::file_coverage(
  source_files = "analysis/R/functions.R",
  test_files = c(
    "analysis/tests/test_coef_or.R",
    "analysis/tests/test_transport_classify.R"
  )
)

percent <- covr::percent_coverage(coverage)
print(percent)

if (percent < 100) {
  stop("Deterministic analysis scope must have 100% line coverage.", call. = FALSE)
}

cat("Deterministic analysis coverage: 100%\n")
