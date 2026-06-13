.libPaths(c("~/R/datafest_libs", .libPaths()))

`%||%` <- function(a, b) if (is.null(a)) b else a

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(ggplot2)
  library(scales)
})
.use_duckdb <- Sys.getenv("DATAFEST_USE_DUCKDB", "1") == "1"
if (.use_duckdb) {
  suppressPackageStartupMessages(library(duckdb))
}

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
DATA_DIR <- file.path(ROOT, "DataFest 2026 - Data Challenge",
                      "Data", "2026-ASA-DataFest-Data-Files")
OUT_DIR  <- file.path(ROOT, "analysis", "output")
FIG_DIR  <- file.path(OUT_DIR, "figures")
TBL_DIR  <- file.path(OUT_DIR, "tables")
LOG_DIR  <- file.path(OUT_DIR, "logs")

CACHE_DIR <- path.expand("~/.datafest_cache")
DB_PATH   <- file.path(CACHE_DIR, "datafest.duckdb")

for (d in c(OUT_DIR, FIG_DIR, TBL_DIR, LOG_DIR, CACHE_DIR)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

CSV <- list(
  patients    = file.path(DATA_DIR, "patients.csv"),
  encounters  = file.path(DATA_DIR, "encounters.csv"),
  diagnosis   = file.path(DATA_DIR, "diagnosis.csv"),
  departments = file.path(DATA_DIR, "departments.csv"),
  providers   = file.path(DATA_DIR, "providers.csv"),
  sdoh        = file.path(DATA_DIR, "social_determinants.csv"),
  tiger       = file.path(DATA_DIR, "tigercensuscodes.csv")
)

connect_db <- function(read_only = FALSE) {
  if (!.use_duckdb) {
    stop("duckdb is disabled (DATAFEST_USE_DUCKDB=0). Unset or set DATAFEST_USE_DUCKDB=1 to use connect_db().",
         call. = FALSE)
  }
  dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = read_only)
}

theme_df <- function() {
  theme_minimal(base_size = 11) +
    theme(
      plot.title.position = "plot",
      plot.title = element_text(face = "bold"),
      plot.subtitle = element_text(color = "grey30"),
      plot.caption = element_text(color = "grey40", hjust = 0),
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
}

save_fig <- function(plot, name, width = 8, height = 5, dpi = 200) {
  ggsave(file.path(FIG_DIR, name), plot, width = width, height = height, dpi = dpi, bg = "white")
  invisible(file.path(FIG_DIR, name))
}

save_tbl <- function(x, name) {
  fwrite(x, file.path(TBL_DIR, name))
  invisible(file.path(TBL_DIR, name))
}

log_note <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste(..., collapse = " "))
  cat(msg, "\n")
  cat(msg, "\n", file = file.path(LOG_DIR, "pipeline.log"), append = TRUE)
}
