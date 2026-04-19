.libPaths(c("~/R/datafest_libs", .libPaths()))
suppressPackageStartupMessages(library(data.table))
ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"
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
cat("smoke_test_outputs: OK\n")
