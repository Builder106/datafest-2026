# RAWGraphs — local viz for the deck (DataFest 2026)

Use **RAWGraphs** ([rawgraphs.io](https://www.rawgraphs.io), [GitHub](https://github.com/rawgraphs/rawgraphs-app)) as an **open-source, browser-based** alternative to hosted tools like Flourish. Data stays **on your machine** when you run the app **locally** (see below).

**CSVs** come from `Rscript analysis/R/06_flourish_export.R` after **`patient_analytic`** exists (or at the end of `run_all.R`). They are split into two folders:

| Folder | File | Rows (2 cohorts × …) |
|--------|------|----------------------|
| **`analysis/output/flourish/annual/`** | `flourish_transport_ed_by_year.csv` | 4 years → 8 rows |
| **`analysis/output/flourish/quarterly/`** | `flourish_transport_ed_by_quarter.csv` | 16 quarters → 32 rows |

**Headless line charts (base R, deck colors #2b7aa1 / #c5462a):** run **`Rscript analysis/R/07_slide4_line_export.R`** after the CSVs exist. It writes matching PNG/SVG (and optional MP4/GIF with **ffmpeg**) into **`analysis/output/figures/slide4_ed_py_annual/`** and **`analysis/output/figures/slide4_ed_py_quarterly/`** so you can compare **annual vs quarterly** person-time versions side by side.

---

## Run RAWGraphs locally (recommended for privacy)

Requires **Node.js** (LTS).

```bash
git clone https://github.com/rawgraphs/rawgraphs-app.git
cd rawgraphs-app
npm ci
npm start
```

Open the URL printed in the terminal (often `http://localhost:3000`). Paste or upload your CSV in the app; nothing in this workflow requires an account.

---

## Which file to load

| CSV | Use in RAWGraphs |
|-----|------------------|
| **`annual/flourish_transport_ed_by_year.csv`** | **Line chart:** **`year`** → x, **`value`** → y, **`cohort`** → color. |
| **`quarterly/flourish_transport_ed_by_quarter.csv`** | **Line chart:** **`t`** (or **`period_start`**) → x, **`value`** → y, **`cohort`** → color — 16 quarterly points per series (smoother animation in Flourish). |
| **`flourish_slope_ed_per_py_2022_2025.csv`** | **Line chart** or **bar chart:** only **2022 and 2025** — good for a **before/after** style graphic (two points per series). |
| **`flourish_slope_ed_per_py_wide.csv`** | If you prefer **one column per cohort** and **one row per year**, use this for **stacked/diverging** layouts that expect wide data. |

**Columns (long files):** `year`, `cohort`, `value`, plus optional `metric`, `n_ed`, `person_years`, `n_patients`, `pct_any_ed` — same definitions as `FLOURISH_VIZ_PROMPT.md`.

---

## Chart types that fit this story

1. **Line chart** (default): two lines over **year**, **value** = ED per person-year, series = **cohort**.
2. **Bar chart** (grouped): **year** on one axis, **value** on the other, **cohort** as grouping/color.
3. **Slope-like read:** use the **four-year** CSV and line chart; or use the **2022 vs 2025** file for a minimal **two-point** line per cohort.

RAWGraphs does **not** export a built-in **Flourish-style auto animation**. For motion without Flourish:

- Run **`07_slide4_line_export.R`** (with ffmpeg) for an **MP4** (or **GIF**) you can insert in Google Slides / PowerPoint / Keynote, or  
- Export **SVG** or **PNG** from RAWGraphs and animate in-deck (transitions) or **screen-record** a scrubbed view, or  
- Use **Flourish** in the browser if the team accepts hosted tooling for that slide.

---

## Colors (match R figures)

- **No transport barrier:** `#2b7aa1`  
- **Transport barrier:** `#c5462a`  
- Light **neutral** background; no neon.

In RAWGraphs, set series colors in the **palette** step before export.

---

## Slide / PDF wording

Replace **“INTERACTIVE COMPONENT: FLOURISH”** on Slide 4 with something like: **“Chart: RAWGraphs (local) · ED per person-year by cohort”** and embed the **exported PNG or SVG**, or a **short MP4** if you record locally.

---

## One-line build prompt (for AI or notes)

Build a **line chart** (2022–2025) of **ED visits per person-year** for two cohorts: **No transport barrier** vs **Transport barrier** (screened patients only). CSV columns: `year`, `cohort`, `value`. Colors **#2b7aa1** and **#c5462a**, white background, large axis labels, no causal claims. Export **PNG 1920×1080** for PowerPoint.
