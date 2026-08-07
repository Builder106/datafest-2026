# DataFest 2026 Pipeline Architecture

This document describes the design, schema, and technical safeguards of Team 13's reproducible R + DuckDB analytics pipeline.

## 1. Pipeline Stages & Execution Flow

```
[Raw CSVs] ──> 01_etl.R ──> [DuckDB Storage] ──> 02_eda.R ──> [Summary Stats]
                                   │
                                   ├──> 03_journey.R ──> [Patient Table]
                                   │                           │
                                   │                           ├──> 04_analyses.R (GLM)
                                   │                           ├──> 05_figures.R (ggplot2)
                                   │                           └──> 08_sensitivity_analysis.R (IPW)
                                   │
                                   └──> 06_flourish_export.R ──> [Flourish CSVs]
```

## 2. DuckDB Schema & Key Invariants

The local columnar database (`~/.datafest_cache/datafest.duckdb`) organizes ~7.6M encounter rows across 7 primary tables:
- **`encounters`**: Core encounter records (`EncounterKey`, `PatientKey`, `EncounterDate`, `IsEdVisit`, `IsInpatientAdmission`).
- **`sdoh`**: Social Determinants of Health questionnaire responses. Transportation exposure is collapsed to `ever_transport_barrier` (ever Yes vs ever No).
- **`diagnoses`**: ICD-10 diagnosis mappings (`PrimaryDiagnosisKey`, `ICD10Code`, `GroupCode`).

### Safeguards & Invariants
1. **Index-Free Execution**: DuckDB v1.3 index creation on nullable BIGINT columns is bypassed; queries rely entirely on vectorized hash joins.
2. **Self-Locating Portable ROOT**: Every R script resolves paths relative to its script location via `--file=` parameter, `DATAFEST_ROOT` environment override, or working directory fallback.
3. **Base-R Graphics Fallback**: `05_figures_base.R` provides an un-depended parachute renderer if `ggplot2`/`rlang` fails in restricted competition environments.

## 3. Statistical Framing

- **Observational Screening Caution**: Absolute prevalences are restricted to the screened subset ($n = 58,639$).
- **Confounding Control**: Multivariable logistic regression adjusts for age bins and sex. Sensitivity analysis (`08_sensitivity_analysis.R`) provides E-value bounds for potential unmeasured confounding.
