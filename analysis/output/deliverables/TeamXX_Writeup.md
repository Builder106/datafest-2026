---
title: "When a ride is the missing treatment"
subtitle: "Transportation barriers and acute-care patient journeys at Stormont Vail Health (2022–2025)"
author: "Team XX --- DataFest 2026, Wesleyan University"
date: "April 19, 2026"
geometry: "left=0.7in,right=0.7in,top=0.6in,bottom=0.6in"
fontsize: 10pt
mainfont: "Helvetica"
colorlinks: true
---

**Question.** Using the longitudinal EHR data, we asked: *do patients who report a transportation barrier experience measurably different healthcare journeys than otherwise similar patients?* If yes, this is an upstream, actionable signal — a social determinant that the health system can act on with shuttle programs, tele-visits, or case management.

**Data & methods.** We used the full DataFest 2026 release from Stormont Vail Health: **7,675,801 encounters** for **947,685 patients**, 2022-01-01 through 2025-12-31, joined to diagnoses, departments, providers, and the 12-domain social-determinants (SDOH) questionnaire. We ingested the seven CSV files into a local DuckDB database for columnar queries, parsed `Date` + `TimeOfDayKey` into an encounter timestamp, and built a patient-level analytic table with per-patient encounter counts, ED/inpatient/observation flags, median gap-days between consecutive encounters, and merged demographics.

From the *Transportation Needs* SDOH domain we derived a three-level exposure: **barrier** (patient ever answered *Yes* to either transportation question, n = 2,986), **no barrier** (ever answered *No*, never *Yes*, n = 55,653), and **declined / unable** (n = 1,438). Non-screened patients (299,699) were kept as context but excluded from comparative tests. Headline outcomes: ED visits per person-year, inpatient admits per person-year, the probability of any ED / any inpatient visit, and — as a diagnosis-anchored check — the % of patients with any ED visit in the 180 days *after* their first encounter for one of four major chronic conditions (hypertension I10, type-2 diabetes E11, CKD N18, atrial fibrillation I48).

**Key findings.**

1. **Transport-barrier patients use 3–4× more acute care.** They average **1.94 ED visits per person-year** vs **0.48** for no-barrier patients, and **0.70 inpatient admits/py** vs **0.22**. Any-ED prevalence is **68 % vs 43 %**; any-inpatient is **63 % vs 35 %**.
2. **The signal survives age and sex adjustment.** In a logistic model (`outcome ~ transport + age + sex`, n = 58,639 screened patients), reporting a barrier carries an **adjusted OR of 3.17 (95 % CI 2.93–3.43)** for any ED use and **3.49 (3.23–3.77)** for any inpatient admission — even though barrier patients are *younger* (median age 51 vs 61), ruling out an age artifact.
3. **The gap persists inside each chronic disease.** Restricting to patients who have a hypertension, diabetes, CKD, or AFib index encounter, the 180-day ED-return rate roughly **doubles** for barrier patients (hypertension: **33 % vs 15 %**; type-2 diabetes: **40 % vs 17 %**; CKD: **37 % vs 21 %**; AFib: **34 % vs 24 %**). Barrier patients *also* visit more often (median 4-day gap vs 8-day), suggesting a reactive, unscheduled pattern rather than missed care.

**Caveats.** (i) Only **61,052 of 947,685** patients (~6 %) have any transportation answer; selection into screening is non-random, so absolute prevalences should not be projected to the whole system. (ii) **20 %** of encounters carry a `PrimaryDiagnosisKey` that is not in the diagnosis lookup (known data-issue per the Q&A), so the chronic-disease cohort is a lower bound. (iii) **65 %** of patients have no parseable FIPS code, so we did not build a geographic model. (iv) `DepartmentType` is labeled `*Unknown` for 71 % of rows, so we used boolean encounter flags (`IsEdVisit`, `IsInpatientAdmission`, …) for setting. (v) Patient journeys are right- and left-censored at the 2022-01-01 / 2025-12-31 window; rates are annualized by observed follow-up.

**Implication.** A single question — *"has lack of transportation kept you from medical appointments?"* — identifies a cohort with **~3× odds** of needing acute care, independent of age. That is a high-yield target for intervention: reliable rides, co-located pharmacy delivery, and tele-visits for chronic-disease follow-up. Acting on the transport answer that *Stormont Vail already collects* is a concrete next step.

*Code and reproducible pipeline (R + DuckDB) accompany this write-up as `TeamXX_Code.txt`.*
