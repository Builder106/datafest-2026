# Contributing

This repo is a **frozen hackathon submission** (Wesleyan DataFest 2026, Team 13). The findings and the deliverable PDFs in the root reflect what was submitted to the judges on April 19, 2026 and are not changing.

That said, the pipeline is open source and reusable. Bug fixes, reproducibility improvements, and follow-on analyses are welcome — see *Scope* below.

## Development setup

You need a recent R (4.3+), the DuckDB CLI (`brew install duckdb`), and ffmpeg (`brew install ffmpeg`) for the Slide 4 animation export. Then:

```bash
# R packages into an isolated lib path (avoids polluting the system library)
Rscript -e 'install.packages(c("data.table","duckdb","DBI","dplyr","tidyr","stringr","lubridate","ggplot2","scales"), lib="~/R/datafest_libs")'

# Drop the official DataFest 2026 CSV bundle into:
# DataFest 2026 - Data Challenge/Data/2026-ASA-DataFest-Data-Files/

# Full pipeline (builds DuckDB on first run at ~/.datafest_cache/datafest.duckdb)
Rscript analysis/R/run_all.R

# Smoke tests
Rscript analysis/tests/smoke_test_outputs.R
```

If `library(duckdb)` segfaults in R (a known issue on some macOS configurations), use the CLI-only Flourish exporter:

```bash
DATAFEST_FLOURISH_CLI_ONLY=1 Rscript analysis/R/06_flourish_export.R
# or call the shell script directly:
bash analysis/sh/flourish_export_duckdb_cli.sh
```

The full run order, paths, and outputs are documented in **[analysis/README.md](analysis/README.md)**.

## Project-specific guardrails

- **Numbered R scripts** (`00_…` → `07_…`) are a run-order contract. New steps slot into the existing sequence; don't insert a step that depends on a later one.
- **`00_config_paths.R`** is the single source of truth for paths. New scripts must import paths from it, not hard-code.
- **DuckDB is the columnar store, not a transactional DB.** Don't write per-row `INSERT`s — bulk-load via `dbWriteTable` or `read_csv_auto`. The 7.6M-row encounter table is the perf floor; anything slower than ~5s for a cohort query is a regression.
- **No `dplyr` in figure-generation scripts.** `05_figures_base.R` exists as a fallback because `dplyr` / `rlang` crashed on some judge laptops during the event. Keep that path working.
- **Smoke tests must pass.** `analysis/tests/smoke_test_outputs.R` is the gate: cohort sizes, OR point estimates, and figure file existence. CI runs the R syntax check; the smoke test requires the (gitignored) data.
- **Never commit the EHR/SDOH data.** The `.gitignore` excludes the `Data/` folder and `.duckdb` files. Don't loosen those rules.

## Commit conventions

The existing log uses short imperative subjects ending in a period:

```
Add 07_slide4_line_export: PNG/SVG from flourish_transport_ed_by_year.csv.
Fix slide4 animation: keep completed segments visible (polyline through seg).
Split Flourish annual vs quarterly exports into separate folders; slide4 figures match.
```

Match that. No Conventional Commits prefix (`feat:`, `fix:`) is in use here. No co-author trailer for AI tooling.

## PR process

1. Open an issue first for anything beyond a one-file bug fix — easier to align on scope before code review.
2. Run `Rscript analysis/tests/smoke_test_outputs.R` locally before opening a PR.
3. CI (R syntax check) must be green.
4. Squash-merge into `main`.

## Scope

**In scope — happy to review:**
- Bug fixes in the existing pipeline scripts.
- Performance improvements that don't change results.
- Documentation, README, and `analysis/README.md` clarifications.
- Smoke-test coverage expansions.
- Reproducibility on additional platforms (Linux, Windows).
- New SQL views in `analysis/sql/` that don't require schema changes.

**Out of scope — will likely close:**
- Changes to the submitted findings, cohort definitions, or model specs. Those are part of the historical submission.
- Switching the analysis stack (e.g. Python rewrite, Polars, Postgres). The point of the repo is the R + DuckDB pipeline as judged.
- Re-running the pipeline against a different dataset and replacing the writeup numbers. That's a fork, not a PR.
- Style-only commits without a substantive change.
- Adding the EHR/SDOH data files to the repo.

If you're unsure where your change lands, open an issue and ask before coding.
