# How well does a tracker setting decide "supported rate" vs "out of range"?
# Constant-rate recordings (clean and with chop) from 15 to 180 strokes/min.
# For each true rate, share of seconds (after 25 s) that are: correct (display within
# 10 % of the true rate), blank, or wrong (a number that is off by more than 10 %).
# Usage: Rscript experiments/range_eval.R SYNTH_DIR prefix label "lab args"   (prefix rt_ or rv_)
suppressMessages(library(tidyverse))
args <- commandArgs(trailingOnly = TRUE)
dir <- args[[1]]; prefix <- args[[2]]; label <- args[[3]]
par <- if (length(args) >= 4) strsplit(args[[4]], " +")[[1]] else character()
lab <- ".pio/rate_lab"
rates <- c(15, 20, 25, 28, 32, 35, 45, 60, 80, 100, 108, 115, 125, 135, 150, 180)
one <- function(kind, r) {
  out <- tempfile(fileext = ".csv")
  system2(lab, c("fast=1", par), stdin = file.path(dir, str_c(prefix, kind, r, ".csv")), stdout = out, stderr = FALSE)
  d <- read_csv(out, na = "NA", show_col_types = FALSE) |> filter(t_s >= 25)
  tibble(kind, rate = r, n = nrow(d), correct = mean(!is.na(d$A) & abs(d$A - r) <= 0.1 * r), blank = mean(is.na(d$A)), wrong = mean(!is.na(d$A) & abs(d$A - r) > 0.1 * r))
}
res <- map(c("clean", "chop"), \(k) map(rates, \(r) one(k, r)) |> list_rbind()) |> list_rbind()
zone <- \(r) case_when(r >= 32 & r <= 105 ~ "inside (32-105)", r <= 26 | r >= 125 ~ "outside (<=26, >=125)", TRUE ~ "edge")
tab <- res |> mutate(zone = zone(rate)) |> group_by(zone, kind) |> summarise(correct = mean(correct), blank = mean(blank), wrong = mean(wrong), .groups = "drop")
cat(sprintf("== %s (%s) ==\n", label, prefix))
options(tibble.width = Inf)
print(tab |> mutate(across(where(is.double), \(v) round(100 * v))))
if (Sys.getenv("DETAIL") != "") print(res |> mutate(across(c(correct, blank, wrong), \(v) round(100 * v))), n = 100)
