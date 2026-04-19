ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"
CSV <- file.path(ROOT, "analysis/output/flourish/flourish_transport_ed_by_year.csv")
FIG <- file.path(ROOT, "analysis/output/figures")

pal_nb <- "#2b7aa1"
pal_tb <- "#c5462a"

df <- read.csv(CSV, stringsAsFactors = FALSE)
nb <- df[df$cohort == "No transport barrier", ]
tb <- df[df$cohort == "Transport barrier", ]
nb <- nb[order(nb$year), ]
tb <- tb[order(tb$year), ]

y_r <- range(df$value)
y_r[1] <- max(0, y_r[1] * 0.95)
y_r[2] <- y_r[2] * 1.08

draw <- function() {
  par(mar = c(4.5, 4.5, 4, 2))
  plot(nb$year, nb$value,
       type = "l", lwd = 2.5, col = pal_nb,
       xlim = range(df$year) + c(-0.15, 0.15), ylim = y_r,
       xlab = "Calendar year", ylab = "ED visits per person-year",
       xaxt = "n", las = 1
  )
  axis(1, at = unique(df$year))
  lines(tb$year, tb$value, lwd = 2.5, col = pal_tb)
  points(nb$year, nb$value, pch = 19, cex = 1.1, col = pal_nb)
  points(tb$year, tb$value, pch = 19, cex = 1.1, col = pal_tb)
  legend(
    "topleft",
    legend = c("No transport barrier", "Transport barrier"),
    col = c(pal_nb, pal_tb), lwd = 2.5, pch = 19,
    bty = "n", cex = 0.95
  )
  title(
    main = "ED visit intensity by calendar year (screened cohort)",
    cex.main = 1.05, font.main = 2
  )
  mtext(
    "DataFest 2026 · person-time within each calendar year · regional health system",
    side = 3, line = 0.3, cex = 0.65, col = "grey35"
  )
}

png(file.path(FIG, "slide4_ed_per_py_by_year_line.png"), width = 11 * 100, height = 6 * 100, res = 100)
draw()
dev.off()

svg(file.path(FIG, "slide4_ed_per_py_by_year_line.svg"), width = 11, height = 6)
draw()
dev.off()

cat("Wrote:\n ", file.path(FIG, "slide4_ed_per_py_by_year_line.png"), "\n ",
    file.path(FIG, "slide4_ed_per_py_by_year_line.svg"), "\n", sep = "")
