.libPaths(c("~/R/datafest_libs", .libPaths()))
# Resolve repo root portably (Rscript or source(); override via DATAFEST_ROOT)
ROOT <- local({
  e <- Sys.getenv("DATAFEST_ROOT")
  if (nzchar(e)) return(normalizePath(e, mustWork = FALSE))
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", grep("^--file=", a, value = TRUE))
  self <- if (length(f)) gsub("~+~", " ", f[[1]], fixed = TRUE) else {
    p <- NULL
    for (i in rev(seq_len(sys.nframe()))) {
      o <- tryCatch(get("ofile", envir = sys.frame(i), inherits = FALSE),
                    error = function(e) NULL)
      if (!is.null(o)) { p <- o; break }
    }
    p
  }
  if (is.null(self)) normalizePath(getwd(), mustWork = FALSE)
  else normalizePath(file.path(dirname(self), "..", ".."), mustWork = FALSE)
})

suppressPackageStartupMessages(library(data.table))
source(file.path(ROOT, "analysis", "R", "00_config_paths.R"))

log_note("05_figures_base: start (base graphics + data.table only; no ggplot2)")

status_levels <- c("no_barrier", "barrier")
status_labels_short <- c("No transport barrier", "Transport barrier")
pal <- c("no_barrier" = "#2b7aa1", "barrier" = "#c5462a")

headline <- as.data.table(fread(file.path(TBL_DIR, "an_headline_by_transport.csv")))
rates    <- as.data.table(fread(file.path(TBL_DIR, "an_annualized_rates_by_transport.csv")))
set_mix  <- as.data.table(fread(file.path(TBL_DIR, "an_setting_mix_by_transport.csv")))
chronic  <- as.data.table(fread(file.path(TBL_DIR, "an_chronic_followup_by_transport.csv")))
ors      <- as.data.table(fread(file.path(TBL_DIR, "an_logit_or_transport.csv")))

headline <- headline[transport_status %in% status_levels]
rates    <- rates   [transport_status %in% status_levels]
set_mix  <- set_mix [transport_status %in% status_levels]

panel_df <- rbind(
  data.table(metric = "ED visits / person-year",
             transport_status = rates$transport_status,
             value = rates$ed_per_person_year),
  data.table(metric = "Inpatient admits / person-year",
             transport_status = rates$transport_status,
             value = rates$inpat_per_person_year),
  data.table(metric = "% patients with any ED visit",
             transport_status = headline$transport_status,
             value = headline$pct_any_ed),
  data.table(metric = "% patients admitted to hospital",
             transport_status = headline$transport_status,
             value = headline$pct_any_inpat)
)
panel_df[, metric := factor(metric,
  levels = c("ED visits / person-year",
             "Inpatient admits / person-year",
             "% patients with any ED visit",
             "% patients admitted to hospital"))]
panel_df[, label := ifelse(grepl("^%", metric),
                           sprintf("%.0f%%", 100 * value),
                           sprintf("%.2f", value))]

log_note("Figure 1 (base)")
png(file.path(FIG_DIR, "fig1_transport_journey_signature.png"), width = 9 * 200, height = 6 * 200, res = 200)
par(oma = c(0, 0, 3, 0), mfrow = c(2, 2), mar = c(4, 4, 3, 1))
metric_levels <- levels(panel_df$metric)
for (m in metric_levels) {
  sub <- panel_df[metric == m][order(transport_status)]
  vals <- sub$value
  bp <- barplot(
    vals,
    names.arg = status_labels_short,
    col = c(pal[["no_barrier"]], pal[["barrier"]]),
    main = m,
    ylab = if (grepl("^%", m)) "Share" else "Rate",
    las = 1,
    cex.names = 0.65,
    ylim = c(0, max(vals, na.rm = TRUE) * 1.2)
  )
  text(bp, vals + max(vals, na.rm = TRUE) * 0.02, labels = sub$label, pos = 3, cex = 0.85, font = 2)
}
mtext("Patients who report a transport barrier use 3–4x more acute care", outer = TRUE, line = 1.8, font = 2, cex = 1.1)
mtext("Stormont Vail Health, Jan 2022 – Dec 2025. Screened adult patients only.", outer = TRUE, line = 0.5, cex = 0.85, col = "grey30")
mtext("Source: DataFest 2026. 'Barrier' = patient answered 'Yes' to any Transportation Needs question.",
      side = 1, outer = TRUE, line = -1.2, cex = 0.7, col = "grey40", adj = 0)
dev.off()

log_note("Figure 2 (base forest)")
or_fig <- ors[term == "transportbarrier", .(model, odds_ratio, or_lo, or_hi)]
or_fig[, outcome := ifelse(model == "any_ED",
                           "Any ED visit (≥1 in 4y)",
                           "Any inpatient admission (≥1 in 4y)")]
or_fig[, label := sprintf("OR %.2f (%.2f–%.2f)", odds_ratio, or_lo, or_hi)]
or_fig[, label_x := or_hi + (max(or_hi) - 1L) * 0.06 + 0.06]
or_ord <- or_fig[order(odds_ratio)]
n_or <- nrow(or_ord)
xl <- c(1, max(or_ord$label_x, na.rm = TRUE) * 1.08)

png(file.path(FIG_DIR, "fig2_transport_adjusted_or.png"), width = 9 * 200, height = 3.8 * 200, res = 200)
par(mar = c(5, 18, 6, 2))
plot(NA, xlim = xl, ylim = c(0.5, n_or + 0.5), xlab = "Odds ratio vs no transport barrier",
     ylab = "", yaxt = "n", bty = "n", main = "")
abline(v = 1, lty = 2, col = "grey40")
axis(2, at = seq_len(n_or), labels = or_ord$outcome, las = 1, cex.axis = 0.85)
for (i in seq_len(n_or)) {
  yi <- i
  segments(or_ord$or_lo[i], yi, or_ord$or_hi[i], yi, col = pal[["barrier"]], lwd = 3, lend = 2)
  points(or_ord$odds_ratio[i], yi, pch = 19, col = pal[["barrier"]], cex = 1.3)
  text(or_ord$label_x[i], yi, labels = or_ord$label[i], pos = 4, offset = 0.2, cex = 0.85)
}
title(main = "Transport barrier raises odds of acute care ~3× (age- and sex-adjusted)", font = 2, line = 3.8)
title(sub = "Logistic regression on 58,639 screened patients.", line = 4.5, cex.sub = 0.9, col = "grey30")
mtext("Model: outcome ~ transport + age_proxy + sex. Reference: 'No transport barrier'.",
      side = 1, line = 3.8, cex = 0.65, col = "grey40", adj = 0)
dev.off()

log_note("Figure 3 (base stacked)")
mix_long <- melt(set_mix,
                 id.vars = c("transport_status", "total_encs", "n_patients"),
                 measure.vars = c("share_ed", "share_inpatient", "share_obs", "share_hod", "share_opf2f"),
                 variable.name = "setting", value.name = "share")
mix_long[, share_other := 1 - sum(share), by = transport_status]

setting_levels <- c("share_ed", "share_inpatient", "share_obs", "share_hod", "share_opf2f", "share_other")
setting_labels <- c(
  share_ed = "Emergency dept",
  share_inpatient = "Inpatient admit",
  share_obs = "Observation",
  share_hod = "Hospital OP dept",
  share_opf2f = "Outpatient face-to-face",
  share_other = "Other / virtual / labs"
)
other_rows <- unique(set_mix[, .(transport_status, n_patients, total_encs)])
other_rows[, setting := "share_other"]
other_rows[, share := 1 - (set_mix$share_ed + set_mix$share_inpatient +
                           set_mix$share_obs + set_mix$share_hod + set_mix$share_opf2f)]

mix_long2 <- rbind(mix_long[, .(transport_status, setting, share)],
                   other_rows[, .(transport_status, setting, share)])
mix_long2 <- mix_long2[setting %in% setting_levels]
mix_long2[, setting := factor(setting, levels = setting_levels, labels = setting_labels[setting_levels])]

wide <- dcast(mix_long2, setting ~ transport_status, value.var = "share")
mat <- as.matrix(wide[, c("no_barrier", "barrier")])
rownames(mat) <- as.character(wide$setting)
setting_pal_vec <- c("#c5462a", "#8e3b24", "#d28054", "#6fa2c0", "#2b7aa1", "#b8b8b8")

png(file.path(FIG_DIR, "fig3_setting_mix.png"), width = 9 * 200, height = 5 * 200, res = 200)
par(mar = c(8, 4, 6, 2))
barplot(mat, col = setting_pal_vec, legend.text = rownames(mat), args.legend = list(x = "topright", cex = 0.65, inset = c(0.02, 0)),
        ylab = "Share of all encounters", main = "", names.arg = c("No transport barrier", "Transport barrier"))
title(main = "Barrier patients shift toward ED / inpatient care", font = 2, line = 2)
title(sub = "Composition of all encounters per screened group.", line = 0.8, cex.sub = 0.9, col = "grey30")
mtext("SVH, 2022–2025. 'Other' = labs, telemedicine, appointments, outreach.",
      side = 1, line = 5.5, cex = 0.65, col = "grey40", adj = 0)
dev.off()

log_note("Figure 4 (base faceted bars)")
chronic_fu <- chronic[transport_status %in% status_levels]
chronic_fu[, GroupLabel := factor(GroupCode,
  levels = c("ICD-10-CM: I10", "ICD-10-CM: E11", "ICD-10-CM: N18", "ICD-10-CM: I48"),
  labels = c("Hypertension (I10)", "Type 2 diabetes (E11)", "CKD (N18)", "AFib / flutter (I48)"))]
chronic_fu[, n_label := sprintf("n = %s", format(n_patients, big.mark = ","))]

png(file.path(FIG_DIR, "fig4_chronic_ed_180d.png"), width = 11 * 200, height = 4.5 * 200, res = 200)
par(mfrow = c(1, 4), mar = c(10, 4, 6, 2), oma = c(0, 0, 2, 0))
groups <- levels(chronic_fu$GroupLabel)
ymax <- max(chronic_fu$pct_any_ed_180, na.rm = TRUE) * 1.22
for (g in groups) {
  sub <- chronic_fu[GroupLabel == g][order(transport_status)]
  vals <- sub$pct_any_ed_180
  bp <- barplot(
    vals,
    col = c(pal[["no_barrier"]], pal[["barrier"]]),
    names.arg = c("No barrier", "Barrier"),
    ylim = c(0, ymax),
    ylab = if (g == groups[1]) "% with any ED visit within 180d of index" else "",
    main = g,
    cex.names = 0.75,
    cex.main = 0.85
  )
  text(bp, vals + ymax * 0.02, labels = sprintf("%.0f%%", 100 * vals), pos = 3, cex = 0.8, font = 2)
  text(bp, par("usr")[3] + ymax * 0.02, labels = sub$n_label, pos = 1, cex = 0.6, col = "grey35", xpd = NA)
}
mtext("Even within the same chronic diagnosis, transport barriers double ED return", outer = TRUE, line = 2.2, font = 2, cex = 1)
mtext("180-day follow-up after first encounter for each condition, 2022–2025.", outer = TRUE, line = 0.8, cex = 0.85, col = "grey30")
mtext("Includes all index encounters with the specified ICD-10 group. Barrier group is small for some conditions; see n-labels.",
      side = 1, outer = TRUE, line = -1, cex = 0.65, col = "grey40", adj = 0)
dev.off()

log_note("05_figures_base: done")
log_note("When ggplot2 works again, prefer Rscript 05_figures.R for theme-matched output.")
