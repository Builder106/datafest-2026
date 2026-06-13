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
  anim_substeps <- if (quarterly) 8L else 5L
  anim_fps <- 15L
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
  xc_nb <- nb[[x_col]]
  xc_tb <- tb[[x_col]]
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

  draw_anim_smooth <- function(t) {
    plot_axes()
    if (n_steps < 2L) {
      if (n_steps == 1L) {
        points(xc_nb[1], nb$value[1], pch = 19, cex = 1.1, col = pal_nb)
        points(xc_tb[1], tb$value[1], pch = 19, cex = 1.1, col = pal_tb)
      }
      return()
    }
    if (t == 0L) {
      points(xc_nb[1], nb$value[1], pch = 19, cex = 1.1, col = pal_nb)
      points(xc_tb[1], tb$value[1], pch = 19, cex = 1.1, col = pal_tb)
      return()
    }
    seg <- (as.integer(t) - 1L) %/% anim_substeps + 1L
    al <- ((as.integer(t) - 1L) %% anim_substeps + 1L) / anim_substeps
    if (seg >= 2L) {
      lines(xc_nb[seq_len(seg)], nb$value[seq_len(seg)], lwd = 2.5, col = pal_nb)
      lines(xc_tb[seq_len(seg)], tb$value[seq_len(seg)], lwd = 2.5, col = pal_tb)
    }
    xa1 <- xc_nb[seg]
    xa2 <- xc_nb[seg + 1L]
    ya1 <- nb$value[seg]
    ya2 <- nb$value[seg + 1L]
    lines(c(xa1, xa1 + al * (xa2 - xa1)), c(ya1, ya1 + al * (ya2 - ya1)), lwd = 2.5, col = pal_nb)
    xb1 <- xc_tb[seg]
    xb2 <- xc_tb[seg + 1L]
    yb1 <- tb$value[seg]
    yb2 <- tb$value[seg + 1L]
    lines(c(xb1, xb1 + al * (xb2 - xb1)), c(yb1, yb1 + al * (yb2 - yb1)), lwd = 2.5, col = pal_tb)
    points(xc_nb[seq_len(seg)], nb$value[seq_len(seg)], pch = 19, cex = 1.1, col = pal_nb)
    points(xc_tb[seq_len(seg)], tb$value[seq_len(seg)], pch = 19, cex = 1.1, col = pal_tb)
    if (al < 1 - 1e-9) {
      points(xa1 + al * (xa2 - xa1), ya1 + al * (ya2 - ya1), pch = 19, cex = 0.95, col = pal_nb)
      points(xb1 + al * (xb2 - xb1), yb1 + al * (yb2 - yb1), pch = 19, cex = 0.95, col = pal_tb)
    } else {
      points(xa2, ya2, pch = 19, cex = 1.1, col = pal_nb)
      points(xb2, yb2, pch = 19, cex = 1.1, col = pal_tb)
    }
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
      n_hold <- min(12L, max(4L, anim_fps))
      if (n_steps >= 2L) {
        n_body <- 1L + (n_steps - 1L) * anim_substeps
        frame_seq <- c(0L, seq_len((n_steps - 1L) * anim_substeps))
      } else {
        n_body <- max(1L, n_steps)
        frame_seq <- seq_len(n_body) - 1L
      }
      n_frames <- length(frame_seq) + n_hold
      patt_in <- if (n_frames > 99L) "frame_%03d.png" else "frame_%02d.png"
      for (i in seq_along(frame_seq)) {
        png(
          sprintf(patt_in, i),
          width = 11 * 100,
          height = 6 * 100,
          res = 100
        )
        if (n_steps >= 2L) {
          draw_anim_smooth(frame_seq[i])
        } else {
          draw_cumulative(max(1L, n_steps))
        }
        dev.off()
      }
      for (j in seq_len(n_hold)) {
        png(
          sprintf(patt_in, length(frame_seq) + j),
          width = 11 * 100,
          height = 6 * 100,
          res = 100
        )
        if (n_steps >= 2L) {
          draw_anim_smooth((n_steps - 1L) * anim_substeps)
        } else {
          draw_cumulative(max(1L, n_steps))
        }
        dev.off()
      }
      out_mp4 <- file.path(tmp, "out.mp4")
      out_gif <- file.path(tmp, "out.gif")
      st1 <- system2(
        ffmpeg,
        c(
          "-y", "-framerate", as.character(anim_fps),
          "-i", patt_in,
          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
          out_mp4
        ),
        stdout = FALSE, stderr = FALSE
      )
      st2 <- system2(
        ffmpeg,
        c(
          "-y", "-framerate", as.character(anim_fps),
          "-i", patt_in,
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
