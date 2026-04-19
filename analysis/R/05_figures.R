source("/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest/analysis/R/00_config.R")

log_note("05_figures: start")
con <- connect_db(read_only = TRUE)
on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)

status_levels <- c("no_barrier", "barrier")
status_labels <- c("No transport barrier\n(n = 55,653)",
                   "Transport barrier\n(n = 2,986)")
pal <- c("no_barrier" = "#2b7aa1", "barrier" = "#c5462a")

headline <- as.data.table(fread(file.path(TBL_DIR, "an_headline_by_transport.csv")))
rates    <- as.data.table(fread(file.path(TBL_DIR, "an_annualized_rates_by_transport.csv")))
set_mix  <- as.data.table(fread(file.path(TBL_DIR, "an_setting_mix_by_transport.csv")))
chronic  <- as.data.table(fread(file.path(TBL_DIR, "an_chronic_followup_by_transport.csv")))
ors      <- as.data.table(fread(file.path(TBL_DIR, "an_logit_or_transport.csv")))

headline <- headline[transport_status %in% status_levels]
rates    <- rates   [transport_status %in% status_levels]
set_mix  <- set_mix [transport_status %in% status_levels]

log_note("Figure 1: four-panel journey signature")
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
panel_df[, status_lab := factor(transport_status, levels = status_levels, labels = status_labels)]
panel_df[, label := ifelse(grepl("^%", metric),
                           sprintf("%.0f%%", 100 * value),
                           sprintf("%.2f", value))]

p1 <- ggplot(panel_df, aes(status_lab, value, fill = transport_status)) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = label), vjust = -0.3, size = 3.2, fontface = "bold") +
  facet_wrap(~metric, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = pal) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(x = NULL, y = NULL,
       title = "Patients who report a transport barrier use 3–4x more acute care",
       subtitle = "Stormont Vail Health, Jan 2022 – Dec 2025. Screened adult patients only.",
       caption = "Source: DataFest 2026. 'Barrier' = patient answered 'Yes' to any Transportation Needs question.") +
  theme_df()
save_fig(p1, "fig1_transport_journey_signature.png", width = 9, height = 6)

log_note("Figure 2: adjusted odds ratios (age + sex adjusted)")
or_fig <- ors[term == "transportbarrier",
              .(model, odds_ratio, or_lo, or_hi)]
or_fig[, outcome := ifelse(model == "any_ED",
                           "Any ED visit (≥1 in 4y)",
                           "Any inpatient admission (≥1 in 4y)")]

p2 <- ggplot(or_fig, aes(odds_ratio, reorder(outcome, odds_ratio))) +
  geom_vline(xintercept = 1, linetype = 2, color = "grey40") +
  geom_errorbarh(aes(xmin = or_lo, xmax = or_hi), height = 0.15, color = pal[["barrier"]]) +
  geom_point(size = 4, color = pal[["barrier"]]) +
  geom_text(aes(label = sprintf("OR %.2f (%.2f–%.2f)", odds_ratio, or_lo, or_hi)),
            hjust = -0.15, size = 3.4) +
  scale_x_continuous(limits = c(1, max(or_fig$or_hi) * 1.35),
                     breaks = c(1, 2, 3, 4)) +
  labs(x = "Odds ratio vs no transport barrier",
       y = NULL,
       title = "Transport barrier raises odds of acute care ~3× (age- and sex-adjusted)",
       subtitle = "Logistic regression on 58,639 screened patients.",
       caption = "Model: outcome ~ transport + age_proxy + sex. Reference: 'No transport barrier'.") +
  theme_df() +
  theme(panel.grid.major.y = element_blank())
save_fig(p2, "fig2_transport_adjusted_or.png", width = 9, height = 3.8)

log_note("Figure 3: setting mix - share of encounters by setting")
mix_long <- melt(set_mix,
                 id.vars = c("transport_status","total_encs","n_patients"),
                 measure.vars = c("share_ed","share_inpatient","share_obs","share_hod","share_opf2f"),
                 variable.name = "setting", value.name = "share")
mix_long[, share_other := 1 - sum(share), by = transport_status]

setting_labels <- c(
  share_ed        = "Emergency dept",
  share_inpatient = "Inpatient admit",
  share_obs       = "Observation",
  share_hod       = "Hospital OP dept",
  share_opf2f     = "Outpatient face-to-face",
  share_other     = "Other / virtual / labs"
)
other_rows <- unique(set_mix[, .(transport_status, n_patients, total_encs)])
other_rows[, setting := "share_other"]
other_rows[, share := 1 - (set_mix$share_ed + set_mix$share_inpatient +
                           set_mix$share_obs + set_mix$share_hod +
                           set_mix$share_opf2f)]

mix_long2 <- rbind(mix_long[, .(transport_status, setting, share)],
                   other_rows[, .(transport_status, setting, share)])
mix_long2[, setting := factor(setting,
                              levels = c("share_ed","share_inpatient","share_obs",
                                         "share_hod","share_opf2f","share_other"),
                              labels = setting_labels)]
mix_long2[, status_lab := factor(transport_status, levels = status_levels, labels = status_labels)]

setting_pal <- c("Emergency dept"          = "#c5462a",
                 "Inpatient admit"         = "#8e3b24",
                 "Observation"             = "#d28054",
                 "Hospital OP dept"        = "#6fa2c0",
                 "Outpatient face-to-face" = "#2b7aa1",
                 "Other / virtual / labs"  = "#b8b8b8")

p3 <- ggplot(mix_long2, aes(status_lab, share, fill = setting)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = ifelse(share > 0.02, scales::percent(share, accuracy = 1), "")),
            position = position_stack(vjust = 0.5), size = 3, color = "white", fontface = "bold") +
  scale_fill_manual(values = setting_pal) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.02))) +
  labs(x = NULL, y = "Share of all encounters",
       fill = "Care setting",
       title = "Barrier patients shift toward ED / inpatient care",
       subtitle = "Composition of all encounters per screened group.",
       caption = "SVH, 2022-2025. 'Other' = labs, telemedicine, appointments, outreach.") +
  theme_df()
save_fig(p3, "fig3_setting_mix.png", width = 9, height = 5)

log_note("Figure 4: chronic disease follow-up ED burden (180d post-index)")
chronic_fu <- chronic[transport_status %in% status_levels]
chronic_fu[, GroupLabel := factor(GroupCode,
  levels = c("ICD-10-CM: I10","ICD-10-CM: E11","ICD-10-CM: N18","ICD-10-CM: I48"),
  labels = c("Hypertension\n(I10)","Type 2 diabetes\n(E11)","CKD\n(N18)","AFib / flutter\n(I48)"))]
chronic_fu[, status_lab := factor(transport_status, levels = status_levels, labels = status_labels)]
chronic_fu[, n_label := sprintf("n = %s", format(n_patients, big.mark = ","))]

p4 <- ggplot(chronic_fu, aes(status_lab, pct_any_ed_180, fill = transport_status)) +
  geom_col(width = 0.7, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_any_ed_180)),
            vjust = -0.3, size = 3, fontface = "bold") +
  geom_text(aes(label = n_label, y = 0),
            vjust = 1.6, size = 2.8, color = "grey35") +
  facet_wrap(~GroupLabel, nrow = 1) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(NA, max(chronic_fu$pct_any_ed_180) * 1.22),
                     expand = expansion(mult = c(0.08, 0.02))) +
  scale_fill_manual(values = pal) +
  labs(x = NULL, y = "% with any ED visit within 180d of index",
       title = "Even within the same chronic diagnosis, transport barriers double ED return",
       subtitle = "180-day follow-up after first encounter for each condition, 2022-2025.",
       caption = "Includes all index encounters with the specified ICD-10 group. Barrier group is small for some conditions; see n-labels.") +
  theme_df()
save_fig(p4, "fig4_chronic_ed_180d.png", width = 11, height = 4.5)

log_note("Figure 5 (context): patient age distribution by transport status")
pa_df <- as.data.table(dbGetQuery(con, "
  SELECT age_proxy, transport_status
  FROM patient_analytic
  WHERE transport_status IN ('barrier','no_barrier')
    AND age_proxy BETWEEN 0 AND 100;"))
pa_df[, status_lab := factor(transport_status, levels = status_levels, labels = status_labels)]

p5 <- ggplot(pa_df, aes(age_proxy, fill = transport_status)) +
  geom_density(alpha = 0.55, color = NA) +
  scale_fill_manual(values = pal, labels = status_labels) +
  labs(x = "Approx. age (2026 - birth-year bin)",
       y = "Density",
       fill = NULL,
       title = "Barrier patients are younger — so the gap isn't just age",
       subtitle = "Higher ED and inpatient rates persist after age adjustment (see OR plot)") +
  theme_df() + theme(legend.position = "top")
save_fig(p5, "fig5_age_density.png", width = 8, height = 4)

log_note("05_figures: done")
