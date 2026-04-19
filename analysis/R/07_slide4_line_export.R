ROOT <- "/Users/yinkavaughan/My Drive (yvaughan@wesleyan.edu)/DataFest"
OUT_FL <- file.path(ROOT, "analysis/output/flourish")
OUT_FIG <- file.path(ROOT, "analysis/output/figures")
CSV_ANNUAL <- file.path(OUT_FL, "annual", "flourish_transport_ed_by_year.csv")
if (!file.exists(CSV_ANNUAL)) {
  leg <- file.path(OUT_FL, "flourish_transport_ed_by_year.csv")
  if (file.exists(leg)) {
    CSV_ANNUAL <- leg
  }
}
CSV_Q <- file.path(OUT_FL, "quarterly", "flourish_transport_ed_by_quarter.csv")
FIG_ANNUAL <- file.path(OUT_FIG, "slide4_ed_py_annual")
FIG_Q <- file.path(OUT_FIG, "slide4_ed_py_quarterly")

pal_nb <- "#2b7aa1"
pal_tb <- "#c5462a"

export_slide4 <- function(csv, fig_dir, stem, main, xlab, sub, x_col, quarterly) {
  if (!file.exists(csv)) {
    warning("missing ", csv, " — run analysis/R/06_flourish_export.R after 03_journey")
    return(invisible(NULL))
  }
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  df <- read.csv(csv, stringsAsFactors = FALSE)
  nb <- df[df$cohort == "No transport barrier", , drop = FALSE]
  tb <- df[df$cohort == "Transport barrier", , drop = FALSE]
  nb <- nb[order(nb[[x_col]]), , drop = FALSE]
  tb <- tb[order(tb[[x_col]]), , drop = FALSE]
  xv <- df[[x_col]]
  y_r <- range(df$value, na.rm = TRUE)
  y_r[1] <- max(0, y_r[1] * 0.95)
  y_r[2] <- y_r[2] * 1.08
  ux <- sort(unique(nb[[x_col]]))
  x_r <- range(xv, na.rm = TRUE)
  pad <- if (quarterly) diff(range(ux, na.rm = TRUE)) * 0.02 else 0.15
  x_r <- x_r + c(-pad, pad)

  plot_axes <- function() {
    par(mar = c(if (quarterly) 6.5 else 4.5, 4.5, 4, 2))
    plot.new()
    plot.window(xlim = x_r, ylim = y_r)
    axis(2, las = 1)
    if (quarterly && "period_label" %in% names(nb)) {
      ax_at <- c(nb$period_label, tb$period_label)
      ax_x <- c(nb[[x_col]], tb[[x_col]])
      u <- !duplicated(ax_x)
      ax_at <- ax_at[u]
      ax_x <- ax_x[u]
      o <- order(ax_x)
      axis(1, at = ax_x[o], labels = ax_at[o], las = 2, cex.axis = 0.68)
    } else {
      axis(1, at = ux)
    }
    box()
    title(main = main, cex.main = 1.05, font.main = 2)
    mtext(sub, side = 3, line = 0.3, cex = 0.65, col = "grey35")
    mtext(xlab, side = 1, line = if (quarterly) 5 else 3.2)
    mtext("ED visits per person-year", side = 2, line = 3.2)
    legend(
      "topleft",
      legend = c("No transport barrier", "Transport barrier"),
      col = c(pal_nb, pal_tb), lwd = 2.5, pch = 19,
      bty = "n", cex = 0.95
    )
  }

  n_steps <- length(ux)
  draw_cumulative <- function(k) {
    plot_axes()
    kk <- min(k, n_steps)
    nb_k <- nb[seq_len(kk), , drop = FALSE]
    tb_k <- tb[seq_len(kk), , drop = FALSE]
    if (nrow(nb_k) >= 2) {
      lines(nb_k[[x_col]], nb_k$value, lwd = 2.5, col = pal_nb)
    }
    if (nrow(tb_k) >= 2) {
      lines(tb_k[[x_col]], tb_k$value, lwd = 2.5, col = pal_tb)
    }
    points(nb_k[[x_col]], nb_k$value, pch = 19, cex = 1.1, col = pal_nb)
    points(tb_k[[x_col]], tb_k$value, pch = 19, cex = 1.1, col = pal_tb)
  }

  draw_full <- function() {
    draw_cumulative(n_steps)
  }

  png(file.path(fig_dir, paste0(stem, ".png")), width = 11 * 100, height = 6 * 100, res = 100)
  draw_full()
  dev.off()

  svg(file.path(fig_dir, paste0(stem, ".svg")), width = 11, height = 6)
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
      n_hold <- min(4L, max(1L, n_steps %/% 4))
      n_frames <- n_steps + n_hold
      for (i in seq_len(n_frames)) {
        k <- min(i, n_steps)
        png(sprintf("frame_%02d.png", i), width = 11 * 100, height = 6 * 100, res = 100)
        draw_cumulative(k)
        dev.off()
      }
      out_mp4 <- file.path(tmp, "out.mp4")
      out_gif <- file.path(tmp, "out.gif")
      fps <- if (quarterly) 4L else 1L
      st1 <- system2(
        ffmpeg,
        c(
          "-y", "-framerate", as.character(fps),
          "-i", "frame_%02d.png",
          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
          out_mp4
        ),
        stdout = FALSE, stderr = FALSE
      )
      st2 <- system2(
        ffmpeg,
        c(
          "-y", "-framerate", as.character(fps),
          "-i", "frame_%02d.png",
          "-loop", "0", out_gif
        ),
        stdout = FALSE, stderr = FALSE
      )
      if (st1 != 0L) warning("ffmpeg MP4 encode exited with status ", st1)
      if (st2 != 0L) warning("ffmpeg GIF encode exited with status ", st2)
      dest_mp4 <- file.path(fig_dir, paste0(stem, ".mp4"))
      dest_gif <- file.path(fig_dir, paste0(stem, ".gif"))
      invisible(file.copy(out_mp4, dest_mp4, overwrite = TRUE))
      invisible(file.copy(out_gif, dest_gif, overwrite = TRUE))
    })
  }

  cat(
    "Wrote:\n ",
    file.path(fig_dir, paste0(stem, ".png")), "\n ",
    file.path(fig_dir, paste0(stem, ".svg")), "\n",
    sep = ""
  )
  if (nzchar(Sys.which("ffmpeg"))) {
    cat(
      " ", file.path(fig_dir, paste0(stem, ".mp4")), "\n ",
      file.path(fig_dir, paste0(stem, ".gif")), "\n",
      sep = ""
    )
  }
  invisible(fig_dir)
}

export_slide4(
  CSV_ANNUAL,
  FIG_ANNUAL,
  "slide4_ed_per_py_by_year_line",
  "ED visit intensity by calendar year (screened cohort)",
  "Calendar year",
  "DataFest 2026 · person-time within each calendar year · regional health system",
  "year",
  FALSE
)

export_slide4(
  CSV_Q,
  FIG_Q,
  "slide4_ed_per_py_by_quarter_line",
  "ED visit intensity by calendar quarter (screened cohort)",
  "Calendar quarter (start date)",
  "DataFest 2026 · person-time within each quarter · regional health system",
  "t",
  TRUE
)
