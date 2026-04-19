# RAWGraphs — local viz for the deck (DataFest 2026)

Use **RAWGraphs** ([rawgraphs.io](https://www.rawgraphs.io), [GitHub](https://github.com/rawgraphs/rawgraphs-app)) as an **open-source, browser-based** alternative to hosted tools like Flourish. Data stays **on your machine** when you run the app **locally** (see below).

**Same CSVs** as the Flourish export: run `Rscript analysis/R/06_flourish_export.R` after the pipeline has built tables (or `run_all.R`). Files appear under **`analysis/output/flourish/`** (gitignored).

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
| **`flourish_transport_ed_by_year.csv`** | **Line chart:** map **`year`** → x, **`value`** → y, **`cohort`** → color (series). Shows **2022–2025** ED visits per person-year for **No transport barrier** vs **Transport barrier**. |
| **`flourish_slope_ed_per_py_2022_2025.csv`** | **Line chart** or **bar chart:** only **2022 and 2025** — good for a **before/after** style graphic (two points per series). |
| **`flourish_slope_ed_per_py_wide.csv`** | If you prefer **one column per cohort** and **one row per year**, use this for **stacked/diverging** layouts that expect wide data. |

**Columns (long files):** `year`, `cohort`, `value`, plus optional `metric`, `n_ed`, `person_years`, `n_patients`, `pct_any_ed` — same definitions as `FLOURISH_VIZ_PROMPT.md`.

---

## Chart types that fit this story

1. **Line chart** (default): two lines over **year**, **value** = ED per person-year, series = **cohort**.
2. **Bar chart** (grouped): **year** on one axis, **value** on the other, **cohort** as grouping/color.
3. **Slope-like read:** use the **four-year** CSV and line chart; or use the **2022 vs 2025** file for a minimal **two-point** line per cohort.

RAWGraphs does **not** export a built-in **Flourish-style auto animation**. For the deck you typically:

- Export **SVG** or high-res **PNG** from RAWGraphs and place on the slide, or  
- Export **one PNG per year** and use **PowerPoint transitions**, or  
- **Screen-record** the chart while scrubbing **year** (if you add interaction elsewhere), or  
- Use a short **local** **gganimate** / **MP4** from R for motion (see `FLOURISH_VIZ_PROMPT.md` export section, adapted to static story).

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
