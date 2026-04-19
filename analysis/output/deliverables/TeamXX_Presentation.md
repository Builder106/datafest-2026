---
title: "When a ride is the missing treatment"
subtitle: "Transport barriers and patient journeys at Stormont Vail Health"
author: "Team XX --- DataFest 2026, Wesleyan University"
date: "April 19, 2026"
aspectratio: 169
theme: "default"
colortheme: "seahorse"
innertheme: "rectangles"
outertheme: "infolines"
fontsize: 11pt
header-includes: |
  \setbeamertemplate{navigation symbols}{}
  \setbeamertemplate{footline}{\hfill\insertframenumber\hfill\hfill}
  \setbeamercolor{title}{bg=structure.fg, fg=white}
  \setbeamercolor{frametitle}{bg=structure.fg, fg=white}
  \setbeamerfont{frametitle}{series=\bfseries}
  \usepackage{graphicx}
---

## The question

**Does one SDOH answer — lack of transportation kept me from care — predict a different journey?**

\vspace{0.15em}

**Data.** 7.68 M encounters, 947 K patients (2022–2025). DuckDB + R; encounter flags for ED / inpatient (most `DepartmentType` values are `*Unknown`).

**Cohort** (61,052 screened on *Transportation Needs*):

| Group | n | Rule |
|------:|--:|------|
| No barrier | 55,653 | Ever *No*, never *Yes* |
| **Barrier** | **2,986** | Ever *Yes* |
| Declined | 1,438 | Declined / unable |

## Barrier patients use 3–4× more acute care

\begin{center}
\includegraphics[width=0.90\textwidth]{../figures/fig1_transport_journey_signature.png}
\end{center}

\vspace{-0.8em}

\small Annualized by observed follow-up window (left-/right-censored at 2022-01-01 / 2025-12-31).

## Robustness, disease check, takeaway

\begin{columns}[T,onlytextwidth]
\begin{column}{0.50\textwidth}
\includegraphics[width=\linewidth]{../figures/fig2_transport_adjusted_or.png}
\vspace{-0.35em}
\tiny \textbf{Left:} Logistic `outcome ~ transport + age + sex`, n = 58,639. Barrier patients are *younger* (median 51 vs 61) — effect is not age confounding.
\end{column}
\begin{column}{0.50\textwidth}
\includegraphics[width=\linewidth]{../figures/fig4_chronic_ed_180d.png}
\vspace{-0.35em}
\tiny \textbf{Right:} 180-day ED return after first I10 / E11 / N18 / I48 encounter — barrier roughly doubles ED return within each disease.
\end{column}
\end{columns}

\vspace{0.15em}

\footnotesize
\textbf{Takeaway.} ~3× adjusted odds of any ED / inpatient; high-yield target for shuttles, tele-visits, pharmacy delivery. \textbf{Caveats.} ~6\% screened (selection); 20\% encounters lack matched diagnosis key; 65\% missing FIPS (no geo model). \textbf{One question — ask it more, act on it.}
