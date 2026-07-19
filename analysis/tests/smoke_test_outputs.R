.libPaths(c("~/R/datafest_libs", .libPaths()))
suppressPackageStartupMessages(library(data.table))
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
OUT <- file.path(ROOT, "analysis", "output")
FIG <- file.path(OUT, "figures")
TBL <- file.path(OUT, "tables")
for (f in c(
  file.path(FIG, "fig1_transport_journey_signature.png"),
  file.path(FIG, "fig2_transport_adjusted_or.png"),
  file.path(TBL, "an_headline_by_transport.csv"),
  file.path(TBL, "an_logit_or_transport.csv")
)) stopifnot(file.exists(f))
h <- fread(file.path(TBL, "an_headline_by_transport.csv"))
stopifnot(nrow(h) >= 2)
stopifnot(all(c("no_barrier", "barrier") %in% h$transport_status))
or <- fread(file.path(TBL, "an_logit_or_transport.csv"))
stopifnot(any(or$term == "transportbarrier"))
stopifnot(min(or[term == "transportbarrier", odds_ratio]) > 2.5)
s4a <- file.path(FIG, "slide4_ed_per_py_by_year_line.mp4")
s4q <- file.path(FIG, "slide4_ed_per_py_by_quarter_line.mp4")
for (p in c(s4a, s4q)) {
  stopifnot(file.exists(p))
  stopifnot(file.size(p) > 5000L)
}
cat("smoke_test_outputs: OK\n")
