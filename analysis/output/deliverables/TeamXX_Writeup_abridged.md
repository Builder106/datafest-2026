# DataFest 2026 — findings summary (abridged)

**Question.** Do patients who report a **transportation barrier** use acute care differently than otherwise similar patients? Frame as testable access hypothesis, not blame.

**Data.** Full DataFest 2026 release (treat as **regional health system** on public slides): **7,675,801 encounters**, **947,685 patients**, 2022-01-01 through 2025-12-31. Seven CSVs → DuckDB; encounter timestamps; patient-level table with ED/inpatient flags and demographics.

**Exposure (Transportation Needs).** **Barrier** = ever *Yes* to either transport question, **n = 2,986**. **No barrier** = ever *No*, never *Yes*, **n = 55,653**. **Declined / unable**, **n = 1,438**. **Non-screened** **n = 299,699** kept for context, excluded from comparative models. **61,052** patients have any transport answer.

**Outcomes.** ED and inpatient **per person-year**; probability of **any** ED / **any** inpatient; chronic check — **any ED within 180 days** after first index encounter for **I10, E11, N18, I48**.

**Key findings.** (1) **~3–4×** higher acute use: **1.94 vs 0.48** ED visits per person-year; **0.70 vs 0.22** inpatient admits per person-year; **68% vs 43%** with any ED; **63% vs 35%** with any inpatient. (2) Logistic `outcome ~ transport + age + sex` on screened patients, **n = 58,639**: adjusted **OR 3.17 (95% CI 2.93–3.43)** for any ED and **3.49 (3.23–3.77)** for any inpatient. Barrier patients are **younger** (median age **51 vs 61**), so the effect is **not** an age artifact. (3) Inside chronic cohorts, 180-day ED return about **doubles**: hypertension **33% vs 15%**; type-2 diabetes **40% vs 17%**; CKD **37% vs 21%**; AFib **34% vs 24%**. Median gap between visits **4 vs 8** days (more reactive pattern).

**Caveats.** Only **~6%** of all patients have transport answers — non-random screening; do not extrapolate prevalences system-wide. **~20%** of encounters lack a joinable `PrimaryDiagnosisKey` (chronic slice is conservative). **~65%** of patients lack parseable FIPS (no geography model). **~71%** of encounters have `DepartmentType` *Unknown* — analyses use boolean encounter flags. Follow-up is **left/right censored** at dataset window; rates are annualized by observed time.

**Implication.** One transport screen identifies **~3×** adjusted odds of acute-care need vs no barrier, independent of age — target for rides, tele-visits, pharmacy delivery, case management.

**Compliance.** Aggregate summary only; **no raw rows**. For external decks, prefer **regional health system** over sponsor name unless rules allow.

**Deck / figure alignment.** Slides: `fig1_transport_journey_signature.png` (rates/py); `fig2_transport_adjusted_or.png` (adjusted ORs); `fig4_chronic_ed_180d.png` (180d ED return, I10/E11/N18/I48). Optional: `fig3_setting_mix.png`. Time animation: **RAWGraphs** (local) or static PNG from `analysis/output/flourish/*.csv` — see **`analysis/RAWGRAPHS_VIZ_GUIDE.md`**; ED trajectory **2022–2025**, **barrier vs no barrier**, labels match cohort rules above.
