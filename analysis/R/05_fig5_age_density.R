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

source(file.path(ROOT, "analysis", "R", "00_config_figures.R"))
suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
})

log_note("05_fig5_age_density: start")
con <- dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

status_levels <- c("no_barrier", "barrier")
status_labels <- c("No transport barrier\n(n = 55,653)",
                   "Transport barrier\n(n = 2,986)")
pal <- c("no_barrier" = "#2b7aa1", "barrier" = "#c5462a")

pa_df <- as.data.table(dbGetQuery(con, "
  SELECT age_proxy, transport_status
  FROM patient_analytic
  WHERE transport_status IN ('barrier','no_barrier')
    AND age_proxy BETWEEN 0 AND 100;"))
pa_df[, status_lab := factor(transport_status, levels = status_levels, labels = status_labels)]

p5 <- ggplot(pa_df, aes(age_proxy, fill = transport_status)) +
  geom_density(alpha = 0.55, color = NA) +
  scale_fill_manual(values = pal, labels = status_labels) +
  labs(x = "Approx. age (2026 - birth-year bin)",
       y = "Density",
       fill = NULL,
       title = "Barrier patients are younger — so the gap isn't just age",
       subtitle = "Higher ED and inpatient rates persist after age adjustment (see OR plot)") +
  theme_df() + theme(legend.position = "top")
save_fig(p5, "fig5_age_density.png", width = 8, height = 4)

log_note("05_fig5_age_density: done")
