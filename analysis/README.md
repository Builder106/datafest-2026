# DataFest 2026 analysis (R + DuckDB)

## Run order

1. Install R packages into `~/R/datafest_libs` (see `R/00_config.R` for list): `data.table`, `duckdb`, `DBI`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `ggplot2`, `scales`.
2. Place the official CSV bundle under `DataFest 2026 - Data Challenge/Data/2026-ASA-DataFest-Data-Files/`.
3. From any directory: `Rscript analysis/R/run_all.R` (rebuilds DuckDB at `~/.datafest_cache/datafest.duckdb`). Use `Rscript analysis/R/run_all.R --skip-etl` if the DB already exists.
4. After a full run: `Rscript analysis/tests/smoke_test_outputs.R`.

## Outputs

- Tables: `analysis/output/tables/`
- Figures: `analysis/output/figures/`
- Submission PDFs and code bundle: `analysis/output/deliverables/` (`TeamXX_*` — replace `XX` with team number)

## Deliverable PDFs

Built with pandoc + XeLaTeX from `output/deliverables/TeamXX_*.md`.
