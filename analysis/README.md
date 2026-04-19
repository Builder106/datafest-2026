# DataFest 2026 analysis (R + DuckDB)

## Run order

1. Install R packages into `~/R/datafest_libs` (see `R/00_config.R` for list): `data.table`, `duckdb`, `DBI`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `ggplot2`, `scales`.
2. Place the official CSV bundle under `DataFest 2026 - Data Challenge/Data/2026-ASA-DataFest-Data-Files/`.
3. From any directory: `Rscript analysis/R/run_all.R` (rebuilds DuckDB at `~/.datafest_cache/datafest.duckdb`). Use `Rscript analysis/R/run_all.R --skip-etl` if the DB already exists.
4. After a full run: `Rscript analysis/tests/smoke_test_outputs.R`.
5. Flourish uploads (after `03_journey` exists): `Rscript analysis/R/06_flourish_export.R` (also runs at end of `run_all.R`).

## Outputs

- Tables: `analysis/output/tables/`
- Figures: `analysis/output/figures/`
- Flourish CSVs (gitignored): `analysis/output/flourish/` — see `analysis/FLOURISH_VIZ_PROMPT.md`. Upload **`flourish_slope_ed_per_py_2022_2025.csv`** for a two-year slope chart, or **`flourish_transport_ed_by_year.csv`** for all four years.
- Submission PDFs and code bundle: `analysis/output/deliverables/` (`TeamXX_*` — replace `XX` with team number)

## Deliverable PDFs

Built with pandoc + XeLaTeX from `output/deliverables/TeamXX_*.md`.

## Manus (3000-character chat limit)

Use **`analysis/MANUS_PROMPT_3000.txt`** or repo root **`manus.txt`** for the short paste block (~2.1k chars). Full brief: **`analysis/MANUS_PRESENTATION_PROMPT.md`** (local if gitignored).
