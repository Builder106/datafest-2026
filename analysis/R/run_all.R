.libPaths(c("~/R/datafest_libs", .libPaths()))
args <- commandArgs(trailingOnly = TRUE)
skip_etl <- "--skip-etl" %in% args
if (!skip_etl) {
  source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/01_etl.R")
}
source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/02_eda.R")
source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/03_journey.R")
source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/04_analyses.R")
source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/05_figures.R")
source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/06_flourish_export.R")
cat("run_all: done\n")
