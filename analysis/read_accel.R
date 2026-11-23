# Read a tagvaa log CSV (milestone 4) and plot x/y/z and the magnitude.
#
# Usage:
#   Rscript analysis/read_accel.R path/to/session.csv [output.png]
# or interactively: source("analysis/read_accel.R"); acc <- read_accel("session.csv")
#
# The file may contain extra lines added by the phone app (timestamps, comments,
# repeated headers after a reconnect); only lines that look like
# "seq,t_ms,x_mg,y_mg,z_mg" are kept. A phone-app prefix before the data
# (e.g. "10:31:02.123 ") is stripped.

library(tidyverse)

sample_rate_hz <- 100
large_file_bytes <- 100e6

data_pattern <- "-?\\d+,-?\\d+,-?\\d+,-?\\d+,-?\\d+$"

# Bluefruit Connect UART export (also written by scripts/ble_log.py):
# "Timestamp,Mode,Data", one BLE packet per quoted Data field, with the
# packet's trailing newline stripped. A line can be cut across packets, so
# the stream is rebuilt packet by packet. A packet with a newline starts with
# the tail of a line if its first line is incomplete. A packet without one is
# a whole line or the end of a line when the following packet starts a fresh
# line (its own newline was stripped), and otherwise the start of a line.
# A newline goes before a packet only if the line rebuilt so far is complete
# and the packet does not continue it. Lost packets can still glue fragments
# together; read_accel() drops such lines by plausibility.
# Returns the lines plus a clock table pairing each packet's arrival time on
# the phone (seconds since local midnight) with the t_ms of the last complete
# sample received so far.
unpack_bluefruit <- function(path) {
  packets <- read_csv(path, col_types = "ccc", trim_ws = FALSE) |>
    filter(Mode == "RX", !is.na(Data), Data != "") # a packet of just "\n" arrives empty
  data <- packets$Data
  is_complete <- \(x) str_detect(x, str_c("^", data_pattern)) | str_starts(x, "#") | x == "seq,t_ms,x_mg,y_mg,z_mg"
  has_newline <- str_detect(data, "\n")
  last_line <- str_extract(data, "[^\n]*$")
  first_complete <- is_complete(str_extract(data, "^[^\n]*"))
  n <- length(data)
  next_starts_fresh <- c(first_complete[-1], TRUE)
  continues <- if_else(has_newline, !first_complete, !is_complete(data) & next_starts_fresh)
  starts_with_tail <- continues

  sep <- character(n)       # separator placed before packet k
  current <- character(n)   # last (possibly partial) line after packet k
  for (k in seq_len(n)) {
    if (k == 1) {
      current[k] <- last_line[k]
      next
    }
    sep[k] <- if (is_complete(current[k - 1]) && !starts_with_tail[k]) "\n" else ""
    current[k] <- if (has_newline[k]) last_line[k] else str_c(if (sep[k] == "") current[k - 1] else "", data[k])
  }
  lines <- str_c(sep, data, collapse = "") |> str_split_1("\n")

  clock <- tibble(
    phone_s = period_to_seconds(hms(packets$Timestamp)),
    t_ms = str_match(current, "^-?\\d+,(-?\\d+),-?\\d+,-?\\d+,-?\\d+$")[, 2] |> as.numeric()
  ) |>
    filter(!is.na(t_ms), !is.na(phone_s)) |>
    distinct(t_ms, .keep_all = TRUE) |>
    mutate(phone_s = phone_s + 86400 * cumsum(c(0, diff(phone_s) < -43200))) # past midnight
  list(lines = lines, clock = clock)
}

# Wall-clock time for every sample: a straight-line fit of phone arrival
# time against the Tag's t_ms (absorbs clock drift; BLE latency adds a few
# tens of ms of bias, irrelevant at 1 s resolution).
add_wall_clock <- function(acc, clock, date, tz) {
  fit <- lm(phone_s ~ t_ms, data = clock)
  resid_ms <- 1000 * sd(residuals(fit))
  message(sprintf("clock: %d packets, drift %+.0f ppm, residual sd %.0f ms", nrow(clock), 1e6 * (coef(fit)[[2]] * 1000 - 1), resid_ms))
  midnight <- as.POSIXct(format(date), tz = tz)
  acc |> mutate(time = midnight + predict(fit, newdata = acc))
}

# All text lines of a recording (Bluefruit/ble_log export or plain), plus the
# phone clock table when the export has timestamps.
read_stream_lines <- function(path) {
  if (file.size(path) > large_file_bytes) {
    lines <- data.table::fread(path, sep = NULL, header = FALSE)[[1]]
  } else {
    lines <- read_lines(path)
  }
  if (length(lines) > 0 && lines[[1]] == "Timestamp,Mode,Data") {
    return(unpack_bluefruit(path))
  }
  list(lines = lines, clock = NULL)
}

# Battery voltage lines ("# battery t_ms=... mv=...", once a minute).
read_battery <- function(path) {
  m <- str_match(read_stream_lines(path)$lines, "# battery t_ms=(\\d+) mv=(\\d+)")
  tibble(t_ms = as.numeric(m[, 2]), battery_mv = as.numeric(m[, 3])) |>
    drop_na() |>
    distinct(t_ms, .keep_all = TRUE) |>
    arrange(t_ms)
}

# date: day of the recording (the export only has times of day); defaults to
# the file's modification date. tz: the phone's time zone.
read_accel <- function(path, date = NULL, tz = Sys.timezone()) {
  stream <- read_stream_lines(path)
  lines <- stream$lines
  clock <- stream$clock
  rows <- str_extract(lines, data_pattern)
  rows <- rows[!is.na(rows)]
  if (length(rows) == 0) {
    stop("No data lines found in ", path)
  }

  if (length(rows) > 1e6) {
    acc <- data.table::fread(text = rows, header = FALSE, col.names = c("seq", "t_ms", "x_mg", "y_mg", "z_mg")) |>
      as_tibble()
  } else {
    acc <- read_csv(I(rows), col_names = c("seq", "t_ms", "x_mg", "y_mg", "z_mg"), col_types = "ddddd")
  }

  # Drop lines garbled by lost BLE packets: values beyond +-4.1 g (the range
  # is +-4 g) or a seq that does not fit the seq -> t_ms line.
  n_raw <- nrow(acc)
  acc <- acc |> filter(abs(x_mg) <= 4100, abs(y_mg) <= 4100, abs(z_mg) <= 4100)
  if (nrow(acc) > 10) {
    # robust slope (ms per sample) from random far-apart pairs
    i <- sample.int(nrow(acc), 5000, replace = TRUE)
    j <- sample.int(nrow(acc), 5000, replace = TRUE)
    far <- abs(acc$seq[i] - acc$seq[j]) > 1000
    slope <- median((acc$t_ms[i] - acc$t_ms[j])[far] / (acc$seq[i] - acc$seq[j])[far], na.rm = TRUE)
    if (!is.finite(slope)) slope <- 10
    resid <- acc$t_ms - slope * acc$seq
    acc <- acc[abs(resid - median(resid)) < 2000, ]
  }
  if (nrow(acc) < n_raw) message(sprintf("dropped %d implausible line(s)", n_raw - nrow(acc)))

  acc <- acc |>
    distinct(seq, .keep_all = TRUE) |>
    arrange(seq) |>
    mutate(
      time_s = (seq - first(seq)) / sample_rate_hz,
      across(c(x_mg, y_mg, z_mg), \(v) v / 1000, .names = "{str_remove(.col, '_mg')}_g"),
      mag_g = sqrt(x_g^2 + y_g^2 + z_g^2)
    )

  if (!is.null(clock) && nrow(clock) >= 10) {
    date <- date %||% as.Date(file.mtime(path), tz = tz)
    acc <- add_wall_clock(acc, clock, as.Date(date), tz)
  }
  acc
}

# Gaps in seq mean lost samples (BLE drops or FIFO overruns).
check_gaps <- function(acc) {
  gaps <- acc |>
    mutate(missing = seq - lag(seq) - 1) |>
    filter(missing > 0)
  span_s <- (max(acc$t_ms) - min(acc$t_ms)) / 1000
  n_expected <- max(acc$seq) - min(acc$seq) + 1
  cli_msg <- sprintf(
    "%.0f samples, %.1f s; %.0f lost (%.2f%%) in %.0f gaps; measured rate from t_ms: %.2f Hz",
    nrow(acc), nrow(acc) / sample_rate_hz, n_expected - nrow(acc),
    100 * (n_expected - nrow(acc)) / n_expected, nrow(gaps),
    (n_expected - 1) / span_s
  )
  message(cli_msg)
  invisible(gaps)
}

plot_accel <- function(acc) {
  acc |>
    select(time_s, x_g, y_g, z_g, mag_g) |>
    pivot_longer(-time_s, names_to = "axis", values_to = "g") |>
    mutate(axis = factor(axis, levels = c("x_g", "y_g", "z_g", "mag_g"), labels = c("x", "y", "z", "magnitude"))) |>
    ggplot(aes(time_s, g)) +
    geom_line(linewidth = 0.25) +
    facet_wrap(~axis, ncol = 1, scales = "free_y") +
    labs(x = "time (s)", y = "acceleration (g)") +
    theme_minimal()
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript analysis/read_accel.R session.csv [output.png]")
  }
  acc <- read_accel(args[[1]])
  check_gaps(acc)
  out <- if (length(args) >= 2) args[[2]] else str_replace(args[[1]], "\\.[^.]*$", ".png")
  ggsave(out, plot_accel(acc), width = 12, height = 8, dpi = 120, bg = "white")
  message("Plot written to ", out)
}
