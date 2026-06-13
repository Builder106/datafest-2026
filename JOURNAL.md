# JOURNAL — When a Ride Is the Missing Treatment (DataFest 2026, Team 13)

> Dated log of decisions, pivots, incidents, and quotes. Add entries as
> things happen — retrospectives need this raw material to land.
> Reverse-chronological; one paragraph max per entry.

## 2026-06-13 — Repo move broke every R path; made the pipeline self-locating #incident

A test audit caught that all 14 R scripts (3 configs, the pipeline 01–07, run_all, and `analysis/tests/smoke_test_outputs.R`) hardcoded `ROOT <- ".../My Drive/.../DataFest"` plus absolute `source()` calls — but the repo had moved under `.../CS/Projects/Analyst/DataFest-2026`, so the very first `file.exists()` in the smoke test failed and the whole pipeline was unrunnable. Replaced every hardcoded path with a self-locating `ROOT` block (resolves from the script's own location via `--file=`/`ofile`, two dirs up; honors a `DATAFEST_ROOT` override; falls back to `getwd()`). Two macOS-specific gotchas: `normalizePath(mustWork=FALSE)` won't collapse `../..` for a path that doesn't yet exist, and `commandArgs()` returns the `--file=` value with spaces encoded as `~+~` — so the detector decodes `~+~`→space before resolving. Briefly added a `smoke` CI job to run the test, but reverted it the same day: `analysis/output/{figures,tables}` are gitignored, so the outputs the test checks don't exist on a fresh CI checkout and the job could only fail there. The smoke test stays a LOCAL post-pipeline check (now runnable from anywhere thanks to the portable ROOT); CI keeps to R-syntax + shellcheck.

## 2026-05-20 — Rewrote the writeup in first-person singular #decision

The judges' writeup went from "we" to "I" because the submission ended up solo. The slide deck still says "Team 13 from Wesleyan University" and the talk script reads "we are Team 13," so the deck and the one-pager now disagree on voice on purpose: the deck keeps the team framing it was presented under, the PDF tells the truth about who did the analysis. Worth remembering if anyone later asks why the two deliverables don't match pronoun-for-pronoun.

## 2026-05-18 — Pages site stopped mirroring the README #decision

First cut of `docs/index.html` was the README section-for-section — same banner, same pipeline mermaid, same reproduce steps. That gave the site no reason to exist next to the repo page. Split the audiences instead: README serves developers (reproduce, contribute, code paths), the site serves portfolio viewers (the question, the answer, the evidence). Cut the mermaid, the reproduce block, and the tech-stack list from the landing page; added the four-stat card grid and an inline CSS bar chart sized to the actual 0.48 vs 1.94 ED/PY values. The OG image also had to be re-cut at 1200x630 — it had been pointing at the 1200x420 README banner, which social platforms letterbox and clip.

## 2026-04-19 — Logistic model is the whole argument: OR survives age adjustment #milestone

The headline crude numbers (barrier patients at 1.94 ED visits/person-year vs 0.48, a 4x gap) are easy to wave away as confounding. The load-bearing result is the GLM in `04_analyses.R`: `any_ed ~ transport + age + sex` on n=58,639 screened patients, adjusted OR 3.17 (95% CI 2.93–3.43) for any ED use, 3.49 for any inpatient. The detail that closes the age-confounding objection is that barrier patients are *younger* (median 51 vs 61) — so the effect can't be "older sicker people." Used `age_proxy = 2026 - BirthYearBin` since the data only ships a birth-year *bin*, not a DOB, which is good enough for adjustment but not for anything finer.

## 2026-04-19 — Chronic-cohort check picked four ICD-10 groups to rule out "they're just sicker" #decision

A skeptic's read of the ED gap is that barrier patients simply have more disease. So `03_journey.R` builds a diagnosis-anchored check: take patients with an index encounter for hypertension (I10), type-2 diabetes (E11), CKD (N18), or AFib (I48), then measure 180-day ED return *after* that index visit. The gap roughly doubles inside every cohort (diabetes 40% vs 17%, hypertension 33% vs 15%, CKD 37% vs 21%, AFib 34% vs 24%). Same disease, same condition severity anchor, still a transport gap — that's the line that made the finding feel real rather than mechanical. Picked those four because they're chronic, common, and follow-up-sensitive; the matching keys on `diagnosis.GroupCode` like `ICD-10-CM: I10`, not raw diagnosis values.

## 2026-04-19 — 20% of diagnosis keys don't join, so the chronic cohort is a floor not a count #incident

The QA join in `01_etl.R` surfaced that ~20% of encounter rows carry a `PrimaryDiagnosisKey` with no match in the diagnosis lookup — a known data issue flagged in the sponsor Q&A, not our bug. Decision: don't drop them and don't impute; just state plainly that the chronic-disease cohort is a *lower bound* and let the doubling speak. Also had to dedup the diagnosis table (`ANY_VALUE` per `DiagnosisKey`) because some keys appear on multiple rows. The honest framing — "this is a floor" — went straight into the writeup caveats.

## 2026-04-19 — Killed the geographic model: 65% of patients have no parseable FIPS #pivot

The TIGER census table got loaded and joined on `CensusBlockGroupFipsCode`, and there was a real plan to map transport barriers to block-group population/geography. EDA killed it: 65% of patients have no parseable FIPS code, so any spatial model would be fit on a self-selected third of the sample. Cut it rather than ship a map that looks authoritative and isn't. Same call on setting analysis — `DepartmentType` is `*Unknown` for 71% of rows, so the whole setting/acute-care split runs off the boolean encounter flags (`IsEdVisit`, `IsInpatientAdmission`, `IsObservation`) instead of department labels.

## 2026-04-19 — Defined the exposure as "ever answered Yes," with declined as its own bucket #decision

The transport exposure isn't a single answer — it's derived in `03_journey.R` from two Transportation Needs questions, collapsed per patient: barrier = ever Yes to either (n=2,986), no_barrier = ever No and never Yes (n=55,653), declined/unable = its own group (n=1,438). "Ever Yes" is deliberately sensitive: a barrier reported once still counts, because the claim is about identifying an at-risk cohort, not measuring point prevalence. Kept the ~300k non-screened patients as context but excluded them from the comparisons. Only ~6% of the 947,685 patients are screened at all, and screening is non-random — so absolute prevalences explicitly don't generalize to the whole system.

## 2026-04-19 — DuckDB 1.3 index segfault, so the pipeline runs index-free #incident

Building indexes on the DuckDB tables segfaulted on a nullable BIGINT under DuckDB v1.3. Rather than fight it, `01_etl.R` skips indexes entirely and leans on DuckDB's hash joins, which are fast enough on the ~7.6M-row encounter table that nothing downstream noticed. The `log_note` line — "skipping indexes (rely on DuckDB hash joins to avoid v1.3 index segfault)" — is the breadcrumb left in the code so future-me doesn't "helpfully" add the indexes back and reintroduce the crash.

## 2026-04-19 — ggplot2/rlang crashed, so a base-graphics figure fallback exists #incident

The ggplot2 figure pipeline (`05_figures.R`) crashed via rlang in the competition R environment, with the deck deadline at Sunday noon. Built `05_figures_base.R` as a parachute: same five panels using only `data.table` + base graphics, no dplyr, no ggplot2. Also gated DuckDB loading behind `DATAFEST_USE_DUCKDB` and added a `DATAFEST_FLOURISH_CLI_ONLY` path so the Flourish CSVs can be exported by the DuckDB *command-line* if `library(duckdb)` won't even load in R. Under a same-day deadline, "the chart renders at all" beats "the chart is pretty."

## 2026-04-19 — Repo born private with the data bundle gitignored #decision

DataFest rules: private repos only, no public GitHub with the data, deck, or code, and the data source can't be revealed publicly before May 2. So commit one is a `.gitignore` that excludes the competition CSV bundle, the DuckDB artifacts, the organizer PDFs, and the regenerated outputs — the repo tracks the pipeline and the dictionaries, never the raw EHR. That constraint is why the README's reproduce steps assume you drop your own CSV bundle into place; the data genuinely isn't here and can't be.
