.libPaths(c("~/R/datafest_libs", .libPaths()))

`%||%` <- function(a, b) if (is.null(a)) b else a

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"

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

log_note <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste(..., collapse = " "))
  cat(msg, "\n")
  cat(msg, "\n", file = file.path(LOG_DIR, "pipeline.log"), append = TRUE)
}
