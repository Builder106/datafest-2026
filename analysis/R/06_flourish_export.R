.libPaths(c("~/R/datafest_libs", .libPaths()))

ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"
OUT_DIR <- file.path(ROOT, "analysis", "output")
SQL_DIR <- file.path(ROOT, "analysis", "sql")
CACHE_DIR <- path.expand("~/.datafest_cache")
DB_PATH <- file.path(CACHE_DIR, "datafest.duckdb")
DIR_ANNUAL <- file.path(OUT_DIR, "flourish", "annual")
DIR_Q <- file.path(OUT_DIR, "flourish", "quarterly")
cli_script <- path.expand(file.path(ROOT, "analysis", "sh", "flourish_export_duckdb_cli.sh"))

for (d in c(DIR_ANNUAL, DIR_Q)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

read_sql <- function(name) {
  p <- file.path(SQL_DIR, name)
  paste(readLines(p, warn = FALSE), collapse = "\n")
}

annual_sql <- read_sql("flourish_transport_ed_by_year.sql")
quarterly_sql <- read_sql("flourish_transport_ed_by_quarter.sql")

run_cli <- function() {
  if (!file.exists(cli_script)) {
    stop("missing ", cli_script, call. = FALSE)
  }
  if (!nzchar(Sys.which("bash"))) {
    stop("bash not found", call. = FALSE)
  }
  st <- system2("bash", c(cli_script))
  if (st != 0L) {
    stop("[flourish] DuckDB CLI export failed (exit ", st, ")", call. = FALSE)
  }
}

if (Sys.getenv("DATAFEST_FLOURISH_CLI_ONLY", "") == "1") {
  run_cli()
  quit(save = "no", status = 0)
}

if (!file.exists(DB_PATH)) {
  stop(
    "Database not found: ", DB_PATH,
    "\nRun ETL + journey first, e.g. Rscript analysis/R/run_all.R", call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

con <- dbConnect(duckdb::duckdb(), dbdir = DB_PATH, read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

annual <- as.data.table(dbGetQuery(con, annual_sql))
quarterly <- as.data.table(dbGetQuery(con, quarterly_sql))

fwrite(annual, file.path(DIR_ANNUAL, "flourish_transport_ed_by_year.csv"))
fwrite(quarterly, file.path(DIR_Q, "flourish_transport_ed_by_quarter.csv"))

cat(
  "[flourish] wrote ", nrow(annual), " rows → ",
  file.path(DIR_ANNUAL, "flourish_transport_ed_by_year.csv"), "\n",
  "[flourish] wrote ", nrow(quarterly), " rows → ",
  file.path(DIR_Q, "flourish_transport_ed_by_quarter.csv"), "\n",
  sep = ""
)
