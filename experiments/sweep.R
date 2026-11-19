# Parameter sweep of rate_lab's A and D candidates on synthetic scenarios + the real session.
# Usage: Rscript experiments/sweep.R SYNTH_DIR real_window.csv
# Prints one row per setting: step_s (response to a rate change), steady_sd
# (display jitter on steady stretches), chop_mae / chop_glitch (heavy waves),
# real_sd / real_glitch (the OC1 session, jitter against its own 61 s median).
suppressMessages(library(tidyverse))
suppressMessages(library(slider))
args <- commandArgs(trailingOnly = TRUE)
dir <- args[[1]]
real <- args[[2]]
lab <- ".pio/rate_lab"

run_lab <- function(csv, par) {
  out <- tempfile(fileext = ".csv")
  system2(lab, par, stdin = csv, stdout = out, stderr = FALSE)
  read_csv(out, na = "NA", show_col_types = FALSE)
}

synth_metrics <- function(name, par, cand) {
  d <- run_lab(file.path(dir, str_c(name, ".csv")), par) |>
    inner_join(read_csv(file.path(dir, str_c(name, "_truth.csv")), show_col_types = FALSE), by = "t_s")
  jump <- abs(d$rate - lag(d$rate, default = 0)) >= 5
  d$since <- sequence(rle(cumsum(jump))$lengths) - 1
  p <- d |> filter(rate > 0, t_s >= 8)
  v <- p[[cand]]
  err <- v - p$rate
  changes <- d |> mutate(prev = lag(rate)) |> filter(rate > 0, prev > 0, rate != prev, t_s > 10)
  resp <- pmap_dbl(changes, \(t_s, rate, prev, ...) {
    w <- d |> filter(t_s >= !!t_s, t_s < !!t_s + 25)
    ok <- !is.na(w[[cand]]) & abs(w[[cand]] - rate) <= 0.1 * rate
    i <- which(ok & lead(ok, 1, FALSE) & lead(ok, 2, FALSE))[1]
    if (is.na(i)) 25 else w$t_s[[i]] - t_s
  })
  list(step_s = mean(resp), steady_sd = sd(err[p$since >= 12], na.rm = TRUE), mae = mean(abs(err), na.rm = TRUE), glitch = mean(abs(err) / p$rate > 0.15, na.rm = TRUE))
}

real_metrics <- function(par, cand) {
  d <- run_lab(real, par) |> filter(t_s > 30)
  v <- d[[cand]]
  med <- slide_dbl(v, \(x) median(x, na.rm = TRUE), .before = 30, .after = 30)
  list(sd = sd(v - med, na.rm = TRUE), glitch = mean(abs(v - med) / med > 0.15, na.rm = TRUE), mean = mean(v, na.rm = TRUE))
}

configs <- tribble(
  ~cand, ~tau, ~alpha, ~fast, ~slow,
  "A", 4, 0.15, 2, 6,
  "A", 3, 0.15, 2, 6,
  "A", 2.5, 0.2, 2, 6,
  "A", 2, 0.25, 2, 6,
  "D", 4, 0.15, 1.5, 6,
  "D", 4, 0.15, 1.2, 5,
  "D", 4, 0.15, 1.5, 4,
  "D", 4, 0.2, 1.2, 4
)
res <- pmap(configs, \(cand, tau, alpha, fast, slow) {
  par <- c(tau, alpha, fast, slow)
  st <- synth_metrics("steps", par, cand)
  sc <- synth_metrics("steps_chop", par, cand)
  ch <- synth_metrics("steady_chop", par, cand)
  rl <- real_metrics(par, cand)
  tibble(cand, tau, alpha, fast, slow,
    step_s = mean(c(st$step_s, sc$step_s)), steady_sd = mean(c(st$steady_sd, sc$steady_sd)),
    chop_mae = ch$mae, chop_glitch = 100 * ch$glitch, real_sd = rl$sd, real_glitch = 100 * rl$glitch, real_mean = rl$mean)
}) |> list_rbind()
options(tibble.width = Inf)
print(res |> mutate(across(where(is.double), \(x) round(x, 2))))
