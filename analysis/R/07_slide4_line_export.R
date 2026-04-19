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

years <- sort(unique(nb$year))
x_r <- range(df$year) + c(-0.15, 0.15)

plot_axes <- function() {
  par(mar = c(4.5, 4.5, 4, 2))
  plot.new()
  plot.window(xlim = x_r, ylim = y_r)
  axis(2, las = 1)
  axis(1, at = unique(df$year))
  box()
  title(
    main = "ED visit intensity by calendar year (screened cohort)",
    cex.main = 1.05, font.main = 2
  )
  mtext(
    "DataFest 2026 · person-time within each calendar year · regional health system",
    side = 3, line = 0.3, cex = 0.65, col = "grey35"
  )
  mtext("Calendar year", side = 1, line = 3.2)
  mtext("ED visits per person-year", side = 2, line = 3.2)
  legend(
    "topleft",
    legend = c("No transport barrier", "Transport barrier"),
    col = c(pal_nb, pal_tb), lwd = 2.5, pch = 19,
    bty = "n", cex = 0.95
  )
}

draw_cumulative <- function(k) {
  plot_axes()
  yn <- years[seq_len(k)]
  nb_k <- nb[nb$year %in% yn, , drop = FALSE]
  tb_k <- tb[tb$year %in% yn, , drop = FALSE]
  if (nrow(nb_k) >= 2) {
    lines(nb_k$year, nb_k$value, lwd = 2.5, col = pal_nb)
  }
  if (nrow(tb_k) >= 2) {
    lines(tb_k$year, tb_k$value, lwd = 2.5, col = pal_tb)
  }
  points(nb_k$year, nb_k$value, pch = 19, cex = 1.1, col = pal_nb)
  points(tb_k$year, tb_k$value, pch = 19, cex = 1.1, col = pal_tb)
}

draw_full <- function() {
  draw_cumulative(length(years))
}

png(file.path(FIG, "slide4_ed_per_py_by_year_line.png"), width = 11 * 100, height = 6 * 100, res = 100)
draw_full()
dev.off()

svg(file.path(FIG, "slide4_ed_per_py_by_year_line.svg"), width = 11, height = 6)
draw_full()
dev.off()

ffmpeg <- Sys.which("ffmpeg")
if (nzchar(ffmpeg)) {
  local({
    tmp <- tempfile("slide4_anim_")
    dir.create(tmp)
    owd <- getwd()
    setwd(tmp)
    on.exit(
      {
        setwd(owd)
        unlink(tmp, recursive = TRUE)
      }
    )
    n_hold <- 4L
    n_frames <- length(years) + n_hold
    for (i in seq_len(n_frames)) {
      k <- min(i, length(years))
      png(sprintf("frame_%02d.png", i), width = 11 * 100, height = 6 * 100, res = 100)
      draw_cumulative(k)
      dev.off()
    }
    out_mp4 <- file.path(tmp, "out.mp4")
    out_gif <- file.path(tmp, "out.gif")
    st1 <- system2(
      ffmpeg,
      c(
        "-y", "-framerate", "1",
        "-i", "frame_%02d.png",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        out_mp4
      ),
      stdout = FALSE, stderr = FALSE
    )
    st2 <- system2(
      ffmpeg,
      c(
        "-y", "-framerate", "1",
        "-i", "frame_%02d.png",
        "-loop", "0", out_gif
      ),
      stdout = FALSE, stderr = FALSE
    )
    if (st1 != 0L) {
      warning("ffmpeg MP4 encode exited with status ", st1)
    }
    if (st2 != 0L) {
      warning("ffmpeg GIF encode exited with status ", st2)
    }
    dest_mp4 <- file.path(FIG, "slide4_ed_per_py_by_year_line.mp4")
    dest_gif <- file.path(FIG, "slide4_ed_per_py_by_year_line.gif")
    invisible(file.copy(out_mp4, dest_mp4, overwrite = TRUE))
    invisible(file.copy(out_gif, dest_gif, overwrite = TRUE))
  })
} else {
  warning("ffmpeg not on PATH; skipped MP4/GIF animation. Install ffmpeg or add gifski in R.")
}

cat(
  "Wrote:\n ",
  file.path(FIG, "slide4_ed_per_py_by_year_line.png"), "\n ",
  file.path(FIG, "slide4_ed_per_py_by_year_line.svg"), "\n",
  sep = ""
)
if (nzchar(ffmpeg)) {
  cat(
    " ", file.path(FIG, "slide4_ed_per_py_by_year_line.mp4"), "\n ",
    file.path(FIG, "slide4_ed_per_py_by_year_line.gif"), "\n",
    sep = ""
  )
}
