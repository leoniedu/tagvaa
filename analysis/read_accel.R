# Read an OC6 Logger CSV (milestone 4) and plot x/y/z and the magnitude.
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

# Bluefruit Connect UART export: "Timestamp,Mode,Data", one BLE packet per
# quoted Data field, with the packet's trailing newline stripped. A line can
# be cut across two packets; then one side of the cut is not a complete line,
# and the two packets are joined without a newline.
unpack_bluefruit <- function(path) {
  data <- read_csv(path, col_types = "ccc", trim_ws = FALSE) |>
    filter(Mode == "RX") |>
    pull(Data)
  is_complete <- \(x) str_detect(x, str_c("^", data_pattern)) | str_starts(x, "#") | x == "seq,t_ms,x_mg,y_mg,z_mg"
  last_line <- str_extract(data, "[^\n]*$")
  first_line <- str_extract(data, "^[^\n]*")
  joined_cleanly <- is_complete(head(last_line, -1)) & is_complete(first_line[-1])
  sep <- c(if_else(joined_cleanly, "\n", ""), "")
  str_c(data, sep, collapse = "") |> str_split_1("\n")
}

read_accel <- function(path) {
  if (file.size(path) > large_file_bytes) {
    lines <- data.table::fread(path, sep = NULL, header = FALSE)[[1]]
  } else {
    lines <- read_lines(path)
  }
  if (length(lines) > 0 && lines[[1]] == "Timestamp,Mode,Data") {
    lines <- unpack_bluefruit(path)
  }
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

  acc |>
    distinct(seq, .keep_all = TRUE) |>
    arrange(seq) |>
    mutate(
      time_s = (seq - first(seq)) / sample_rate_hz,
      across(c(x_mg, y_mg, z_mg), \(v) v / 1000, .names = "{str_remove(.col, '_mg')}_g"),
      mag_g = sqrt(x_g^2 + y_g^2 + z_g^2)
    )
}

# Gaps in seq mean lost samples (BLE drops or FIFO overruns).
check_gaps <- function(acc) {
  gaps <- acc |>
    mutate(missing = seq - lag(seq) - 1) |>
    filter(missing > 0)
  span_s <- (max(acc$t_ms) - min(acc$t_ms)) / 1000
  n_expected <- max(acc$seq) - min(acc$seq) + 1
  cli_msg <- sprintf(
    "%d samples, %.1f s; %d lost (%.2f%%) in %d gaps; measured rate from t_ms: %.2f Hz",
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
