# Estimate paddle stroke rate from a Paddle Logger recording and compare it
# with the cadence recorded by a watch / bike computer.
#
# Usage:
#   Rscript analysis/stroke_rate.R session.csv [reference.tcx|.fit|.csv] [YYYY-MM-DD]
# writes session_strokes.png (and session_compare.png with a reference).
#
# Interactively:
#   source("analysis/stroke_rate.R")
#   acc <- read_accel("session.csv") |> stroke_signal()
#   strokes <- detect_strokes(acc)
#   est <- rate_per_second(strokes, acc)
#   ref <- read_reference("activity.tcx")
#   cmp <- compare_rates(est, ref)
#
# The pipeline is the plan for the on-device detector (milestone 5): only
# causal filters (EMA, biquads) that are easy to port to C. The surge axis
# is found offline here (PCA over the session); on the device it will be a
# running estimate.

local({
  here <- if (sys.nframe() == 0) dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))) else "analysis"
  source(file.path(here, "read_accel.R"), local = globalenv())
})

params <- list(
  gravity_tau_s = 2,      # low-pass time constant for gravity
  band_hz = c(0.5, 2),    # band-pass around the stroke frequency (30-120 spm)
  bp_stages = 2,          # cascaded biquads (2 = 4th order)
  min_gap_s = 0.6,        # no two strokes closer than this (100 spm)
  level_tau_s = 3,        # time constant of the running signal level
  threshold_k = 0.5,      # peak must exceed k * running mean |signal|
  min_amp_g = 0.02,       # ... and this absolute amplitude
  spm_range = c(30, 110), # intervals outside this are not strokes
  smooth_n = 5            # rolling median over this many intervals
)

# Exponential moving average (one-pole low-pass), causal.
ema <- function(x, tau_s, fs = sample_rate_hz) {
  a <- 1 - exp(-1 / (tau_s * fs))
  as.numeric(stats::filter(a * x, 1 - a, method = "recursive", init = x[[1]]))
}

# RBJ band-pass biquad (0 dB peak), cascaded `stages` times, causal.
bandpass <- function(x, band_hz, stages = 2, fs = sample_rate_hz) {
  f0 <- sqrt(prod(band_hz))
  q <- f0 / diff(band_hz)
  w0 <- 2 * pi * f0 / fs
  alpha <- sin(w0) / (2 * q)
  a0 <- 1 + alpha
  b <- c(alpha, 0, -alpha) / a0
  a <- c(-2 * cos(w0), 1 - alpha) / a0
  for (i in seq_len(stages)) {
    ff <- as.numeric(stats::filter(x, b, sides = 1))
    ff[is.na(ff)] <- 0
    x <- as.numeric(stats::filter(ff, -a, method = "recursive"))
  }
  x
}

# Adds gravity-free vertical and surge (fore-aft) components and the
# band-passed surge signal used for detection.
stroke_signal <- function(acc, p = params) {
  g <- cbind(ema(acc$x_g, p$gravity_tau_s), ema(acc$y_g, p$gravity_tau_s), ema(acc$z_g, p$gravity_tau_s))
  dyn <- cbind(acc$x_g, acc$y_g, acc$z_g) - g
  g_unit <- g / sqrt(rowSums(g^2))
  vert <- rowSums(dyn * g_unit)
  horiz <- dyn - vert * g_unit

  # Surge = direction of largest horizontal motion. The sign is set so the
  # sharpest excursions (the drive) are positive.
  pc <- prcomp(horiz, center = TRUE)$rotation[, 1]
  surge <- as.numeric(horiz %*% pc)
  skew <- mean((surge - mean(surge))^3)
  if (skew < 0) {
    surge <- -surge
    pc <- -pc
  }
  message(sprintf("surge axis in Tag coordinates: x %.2f, y %.2f, z %.2f", pc[[1]], pc[[2]], pc[[3]]))

  acc |>
    mutate(
      vert_g = -vert, # positive = up
      surge_g = surge,
      surge_bp = bandpass(surge, p$band_hz, p$bp_stages)
    )
}

# Peaks of the band-passed surge above an adaptive threshold, at least
# min_gap_s apart (the larger peak wins).
detect_strokes <- function(acc, p = params) {
  x <- acc$surge_bp
  n <- length(x)
  level <- ema(abs(x), p$level_tau_s)
  thresh <- pmax(p$min_amp_g, p$threshold_k * level)
  i <- 2:(n - 1)
  cand <- i[x[i] > x[i - 1] & x[i] >= x[i + 1] & x[i] > thresh[i]]

  min_gap <- p$min_gap_s * sample_rate_hz
  kept <- integer(0)
  for (j in cand) {
    last <- length(kept)
    if (last == 0 || j - kept[[last]] >= min_gap) {
      kept <- c(kept, j)
    } else if (x[j] > x[kept[[last]]]) {
      kept[[last]] <- j
    }
  }

  strokes <- acc[kept, ] |>
    select(any_of(c("seq", "time_s", "time")), surge_bp) |>
    mutate(interval_s = time_s - lag(time_s), spm = 60 / interval_s)
  ok <- !is.na(strokes$spm) & between(strokes$spm, p$spm_range[[1]], p$spm_range[[2]])
  strokes |>
    mutate(
      spm = if_else(ok, spm, NA_real_),
      spm_smooth = slider::slide_dbl(spm, \(v) median(v, na.rm = TRUE), .before = p$smooth_n - 1, .complete = FALSE)
    )
}

# One value per second: the latest smoothed rate, held for up to 5 s
# without strokes (then NA), like a bike computer display.
rate_per_second <- function(strokes, acc, hold_s = 5) {
  time_col <- if ("time" %in% names(acc)) "time" else "time_s"
  secs <- tibble(t = seq(ceiling(min(acc$time_s)), floor(max(acc$time_s)), by = 1))
  idx <- findInterval(secs$t, strokes$time_s)
  last_t <- c(NA, strokes$time_s)[idx + 1]
  out <- secs |>
    mutate(
      time_s = t,
      spm = c(NA, strokes$spm_smooth)[idx + 1],
      spm = if_else(!is.na(last_t) & t - last_t <= hold_s, spm, NA_real_)
    ) |>
    select(-t)
  if (time_col == "time") {
    t0 <- acc$time[[1]] - acc$time_s[[1]]
    out <- out |> mutate(time = t0 + time_s)
  }
  out
}

# Reference cadence (strokes/min) from a watch: .tcx, .fit (needs the
# FITfileR package) or .csv with columns time (ISO 8601) and cadence.
read_reference <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "tcx") {
    doc <- xml2::read_xml(path) |> xml2::xml_ns_strip()
    tp <- xml2::xml_find_all(doc, "//Trackpoint")
    get <- \(xp) xml2::xml_text(xml2::xml_find_first(tp, xp))
    cadence <- coalesce(as.numeric(get("./Cadence")), as.numeric(get(".//RunCadence")))
    ref <- tibble(time = ymd_hms(get("./Time")), ref_spm = cadence)
  } else if (ext == "fit") {
    if (!requireNamespace("FITfileR", quietly = TRUE)) {
      stop("Reading .fit needs FITfileR: install.packages('FITfileR', repos = c('https://grimbough.r-universe.dev', getOption('repos'))), or export TCX instead.")
    }
    rec <- FITfileR::records(FITfileR::readFitFile(path))
    if (!is.data.frame(rec)) rec <- bind_rows(rec)
    ref <- rec |> transmute(time = timestamp, ref_spm = as.numeric(cadence))
  } else {
    ref <- read_csv(path, col_types = cols()) |> transmute(time = ymd_hms(time), ref_spm = as.numeric(cadence))
  }
  ref |> filter(!is.na(time), !is.na(ref_spm))
}

# Aligns estimate and reference to whole seconds and finds the shift of the
# estimate (within +-max_lag_s) with the smallest mean absolute difference,
# counting pauses as 0 spm so that starts and stops of pieces pin the
# alignment. The shift includes clock offset plus both devices' smoothing
# delays. Then reports agreement while paddling.
compare_rates <- function(est, ref, max_lag_s = 60) {
  if (!"time" %in% names(est)) stop("The recording has no wall-clock time (needs a Bluefruit/ble_log export).")
  e <- est |> transmute(sec = round(as.numeric(time)), spm)
  r <- ref |> transmute(sec = round(as.numeric(time)), ref_spm) |> distinct(sec, .keep_all = TRUE)

  lags <- -max_lag_s:max_lag_s
  mae <- map_dbl(lags, \(l) {
    j <- inner_join(e |> mutate(sec = sec + l), r, by = "sec")
    if (nrow(j) < 30) NA_real_ else mean(abs(coalesce(j$spm, 0) - j$ref_spm))
  })
  best <- lags[which.min(mae)]
  tz <- attr(est$time, "tzone") %||% ""
  j <- inner_join(e |> mutate(sec = sec + best), r, by = "sec") |>
    mutate(time = as.POSIXct(sec, origin = "1970-01-01", tz = tz))
  both <- j |> drop_na(spm, ref_spm) |> filter(ref_spm > 0)
  message(sprintf(
    "overlap %d s (%d s paddling); best shift %+d s; while paddling: bias %+.1f spm, MAE %.1f spm, r = %.2f, median ratio est/ref %.2f",
    nrow(j), nrow(both), best, mean(both$spm - both$ref_spm), mean(abs(both$spm - both$ref_spm)),
    cor(both$spm, both$ref_spm), median(both$spm / both$ref_spm)
  ))
  list(joined = j, offset_s = best, lag_mae = tibble(lag_s = lags, mae = mae))
}

plot_strokes <- function(acc, strokes, window_s = NULL) {
  d <- if (is.null(window_s)) acc else filter(acc, between(time_s, window_s[[1]], window_s[[2]]))
  s <- if (is.null(window_s)) strokes else filter(strokes, between(time_s, window_s[[1]], window_s[[2]]))
  sig <- d |>
    select(time_s, surge_g, vert_g, surge_bp) |>
    pivot_longer(-time_s, names_to = "signal", values_to = "g")
  p1 <- ggplot(sig, aes(time_s, g)) +
    geom_line(linewidth = 0.25) +
    geom_point(data = s |> mutate(signal = "surge_bp", g = surge_bp), colour = "#d62728", size = 0.8) +
    facet_wrap(~signal, ncol = 1, scales = "free_y") +
    labs(x = "time (s)", y = "g", title = sprintf("%d strokes detected", nrow(s))) +
    theme_minimal()
  p1
}

plot_compare <- function(cmp) {
  cmp$joined |>
    select(time, estimate = spm, reference = ref_spm) |>
    pivot_longer(-time, names_to = "source", values_to = "spm") |>
    ggplot(aes(time, spm, colour = source)) +
    geom_line(linewidth = 0.4) + # NA (no strokes) breaks the line
    scale_colour_manual(values = c(estimate = "#d62728", reference = "#1f77b4")) +
    labs(x = NULL, y = "strokes / min", colour = NULL,
         title = sprintf("Tag estimate vs reference (estimate shifted %+d s)", cmp$offset_s)) +
    theme_minimal() +
    theme(legend.position = "top")
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) stop("Usage: Rscript analysis/stroke_rate.R session.csv [reference.tcx|.fit|.csv] [YYYY-MM-DD]")
  date <- if (length(args) >= 3) args[[3]] else NULL
  acc <- read_accel(args[[1]], date = date) |> stroke_signal()
  check_gaps(acc)
  strokes <- detect_strokes(acc)
  est <- rate_per_second(strokes, acc)
  message(sprintf("%d strokes; median rate %.1f spm", nrow(strokes), median(strokes$spm, na.rm = TRUE)))
  stem <- str_remove(args[[1]], "\\.[^.]*$")
  ggsave(str_c(stem, "_strokes.png"), plot_strokes(acc, strokes), width = 12, height = 8, dpi = 120, bg = "white")
  if (nrow(strokes) > 0) {
    zoom_start <- strokes$time_s[[ceiling(nrow(strokes) / 2)]]
    ggsave(str_c(stem, "_zoom.png"), plot_strokes(acc, strokes, zoom_start + c(0, 20)), width = 12, height = 8, dpi = 120, bg = "white")
  }
  write_csv(est, str_c(stem, "_spm.csv"))
  if (length(args) >= 2) {
    cmp <- compare_rates(est, read_reference(args[[2]]))
    suppressWarnings(ggsave(str_c(stem, "_compare.png"), plot_compare(cmp), width = 12, height = 5, dpi = 120, bg = "white"))
  }
  message("Written: ", stem, "_strokes.png, _zoom.png, _spm.csv", if (length(args) >= 2) ", _compare.png")
}
