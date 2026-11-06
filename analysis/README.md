# DataFest 2026 analysis (R + DuckDB)

## Run order

1. Install R packages into `~/R/datafest_libs`(see`R/00_config.R`for list):`data.table`, `duckdb`, `DBI`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `ggplot2`, `scales`, `rpart` (normally included with R).
2. Place the official CSV bundle under `DataFest 2026 - Data Challenge/Data/2026-ASA-DataFest-Data-Files/`.
3. From any directory: `Rscript analysis/R/run_all.R`(rebuilds DuckDB at`~/.datafest_cache/datafest.duckdb`). Use `Rscript analysis/R/run_all.R --skip-etl` if the DB already exists.
4. After a full run: `Rscript analysis/tests/smoke_test_outputs.R`.
5. Time-series CSVs for the deck (after `03_journey` exists): **`analysis/sql/`**holds the shared queries;**`analysis/sh/flourish_export_duckdb_cli.sh`**writes the CSVs using the**DuckDB command-line**(`brew install duckdb`). Alternatively `Rscript analysis/R/06_flourish_export.R`uses the**R**`duckdb`package (same queries). If`library(duckdb)`crashes in R, use only the shell script, or run`DATAFEST_FLOURISH_CLI_ONLY=1 Rscript analysis/R/06_flourish_export.R`so R never loads the package.`run_all.R`runs`06` at the end.

## Outputs

- Tables: `analysis/output/tables/`
- Figures: `analysis/output/figures/`
- Flourish/RAWGraphs CSVs (gitignored): **`analysis/output/flourish/annual/`**(`flourish_transport_ed_by_year.csv` — one row per calendar year per cohort) and**`analysis/output/flourish/quarterly/`**(`flourish_transport_ed_by_quarter.csv` — one row per quarter per cohort). Slide 4 exports land in**`figures/slide4_ed_py_annual/`**and**`figures/slide4_ed_py_quarterly/`** (`07_slide4_line_export.R`).
- Submission PDFs and code bundle: `analysis/output/deliverables/` (`TeamXX_*`— replace`XX` with team number)

## Test coverage

CI enforces 100% line coverage for the deterministic analysis scope in
`analysis/R/functions.R`. This scope contains reusable regression helpers (`coef_or()`),
robust missing data imputation (`impute_missing()`, `impute_dt()`), outlier detection
and capping (`calc_outlier_bounds()`, `detect_outliers()`, `cap_outliers()`, `clean_pipeline_features()`),
statistical correlation matrices (`calc_correlation_matrix()`, `calc_feature_correlations()`, `find_top_correlations()`),
Principal Component Analysis (`fit_pca()`, `project_pca()`), and non-linear manifold reduction (`fit_umap()`).
Predictive evaluation helpers (`binary_model_metrics()`, `prepare_model_features()`,
`evaluate_ensemble_models()`) also belong to the coverage scope; synthetic tests check
fold isolation, training-only imputation, scoring, feature ranking and reproducibility.
The data-backed DuckDB pipeline, figures, exports, and generated-output smoke test remain
integration or local reproducibility checks because they require the licensed data bundle
or external tools.

Run the coverage gate with:

```sh
Rscript analysis/tests/run_coverage.R
```

## Predictive model evaluation

`Rscript analysis/R/04b_model_evaluation.R` runs after `03_journey.R` and is included
in `run_all.R`. It reads **raw** `patient_analytic`, bypassing the globally imputed
table so held-out patients cannot influence preprocessing. For each of `any_ed`
and `any_inpatient`, it evaluates screened barrier/no-barrier patients with observed
outcomes. Missing outcomes are excluded and counted in the settings export; patient
IDs must be unique and nonmissing, and each class needs at least five patients.

Predictors are age, the transportation barrier indicator, and fixed female/male
indicators (other/unknown sex is the reference). Encounter counts, utilization
rates, follow-up intervals, and outcome-derived features are excluded. Within each
of five stratified patient folds, numeric missing values use training medians,
with zero for entirely missing training features. There is no global scaling,
outlier capping, feature selection, or tuning.

The models are a training-prevalence baseline and two ensembles of 50 bootstrapped
`rpart` probability trees: bagging uses every feature; random subspace uses a
random subset of `floor(sqrt(p))` features **per tree**. This is a random-subspace
ensemble, not a per-split random forest. Trees use squared-error splits on binary
outcomes, maximum depth 3, minimum split size 20 and minimum leaf size 7. Leaf
means give probabilities; averaging trees also handles single-class bootstraps.
The seed is 2026, and calls preserve the caller's RNG state.

Each outcome writes `model_<outcome>_fold_metrics.csv`, `summary.csv`,
`permutation_importance.csv`, `feature_importance.csv`, and `settings.csv` under
`analysis/output/tables/` (all five names use the outcome prefix). Metrics are
held-out AUC (average ranks for ties), log loss and Brier score; summaries report
unweighted fold means and sample standard deviations. Log loss clips probabilities
to `[1e-15, 1 - 1e-15]`. Feature importance is the increase in held-out log loss
after shuffling one imputed predictor, repeated five times per fold for each
ensemble. Positive values mean worse predictions after shuffling; negative values
are retained. Importance summaries average all fold/permutation results and report
their sample standard deviation, not a confidence interval. Correlated or redundant
features can share importance. Patient-level predictions are returned by the R
helper for auditing but are not exported by the pipeline.

This is retrospective discrimination of utilization in the existing observation
window. Transportation status aggregates answers over that window, so these results
do not establish prospective clinical performance or causal effects. They do not
replace the submitted regressions or findings. Production prediction would require
a timestamped baseline and a separate future outcome window.

## Deliverable PDFs

Built with pandoc + XeLaTeX from `output/deliverables/TeamXX_*.md`.
