.libPaths(c("~/R/datafest_libs", .libPaths()))
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

args <- commandArgs(trailingOnly = TRUE)
skip_etl <- "--skip-etl" %in% args
if (!skip_etl) {
  source(file.path(ROOT, "analysis", "R", "01_etl.R"))
}
source(file.path(ROOT, "analysis", "R", "02_eda.R"))
source(file.path(ROOT, "analysis", "R", "03_journey.R"))
source(file.path(ROOT, "analysis", "R", "04_analyses.R"))
source(file.path(ROOT, "analysis", "R", "05_figures.R"))
source(file.path(ROOT, "analysis", "R", "06_flourish_export.R"))
cat("run_all: done\n")
