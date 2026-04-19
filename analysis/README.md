# DataFest 2026 analysis (R + DuckDB)

## Run order

1. Install R packages into `~/R/datafest_libs` (see `R/00_config.R` for list): `data.table`, `duckdb`, `DBI`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `ggplot2`, `scales`.
2. Place the official CSV bundle under `DataFest 2026 - Data Challenge/Data/2026-ASA-DataFest-Data-Files/`.
3. From any directory: `Rscript analysis/R/run_all.R` (rebuilds DuckDB at `~/.datafest_cache/datafest.duckdb`). Use `Rscript analysis/R/run_all.R --skip-etl` if the DB already exists.
4. After a full run: `Rscript analysis/tests/smoke_test_outputs.R`.
5. Time-series CSVs for the deck (after `03_journey` exists): **`analysis/sql/`** holds the shared queries; **`analysis/sh/flourish_export_duckdb_cli.sh`** writes the CSVs using the **DuckDB command-line** (`brew install duckdb`). Alternatively `Rscript analysis/R/06_flourish_export.R` uses the **R** `duckdb` package (same queries). If `library(duckdb)` crashes in R, use only the shell script, or run `DATAFEST_FLOURISH_CLI_ONLY=1 Rscript analysis/R/06_flourish_export.R` so R never loads the package. `run_all.R` runs `06` at the end.

## Outputs

- Tables: `analysis/output/tables/`
- Figures: `analysis/output/figures/`
- Flourish/RAWGraphs CSVs (gitignored): **`analysis/output/flourish/annual/`** (`flourish_transport_ed_by_year.csv` — one row per calendar year per cohort) and **`analysis/output/flourish/quarterly/`** (`flourish_transport_ed_by_quarter.csv` — one row per quarter per cohort). See **`analysis/RAWGRAPHS_VIZ_GUIDE.md`**. Slide 4 exports land in **`figures/slide4_ed_py_annual/`** and **`figures/slide4_ed_py_quarterly/`** (`07_slide4_line_export.R`).
- Submission PDFs and code bundle: `analysis/output/deliverables/` (`TeamXX_*` — replace `XX` with team number)

## Deliverable PDFs

Built with pandoc + XeLaTeX from `output/deliverables/TeamXX_*.md`.

## Manus (3000-character chat limit)

Use **`analysis/MANUS_PROMPT_3000.txt`** or repo root **`manus.txt`** for the short paste block (~2.1k chars). Full brief: **`analysis/MANUS_PRESENTATION_PROMPT.md`** (local if gitignored).
