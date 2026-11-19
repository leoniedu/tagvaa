# Score the lab output (experiments/rate_lab.cpp) against the true rate of a
# synthetic scenario (experiments/gen_synth.py).
#
# Usage: Rscript experiments/evaluate_synth.R DIR scenario [scenario ...]
# DIR holds <scenario>_lab.csv, <scenario>_truth.csv, <scenario>_strokes.csv.
suppressMessages(library(tidyverse))

candidates <- c(B = "B (on the Tag)", Bn = "Bn (unsmoothed)", Z = "Z zero-crossing", A = "A autocorrelation", D = "D two-speed")
tol <- 0.10 # "close enough" for the step response
glitch_tol <- 0.15

step_response <- function(d, cand, t_change, rate_new) {
  w <- d |> filter(t_s >= t_change, t_s < t_change + 25)
  ok <- !is.na(w[[cand]]) & abs(w[[cand]] - rate_new) <= tol * rate_new
  run3 <- ok & lead(ok, 1, FALSE) & lead(ok, 2, FALSE)
  i <- which(run3)[1]
  if (is.na(i)) NA_real_ else w$t_s[[i]] - t_change
}

stop_response <- function(d, cand, t_stop) {
  w <- d |> filter(t_s >= t_stop, t_s < t_stop + 15)
  i <- which(is.na(w[[cand]]))[1]
  after <- w |> filter(t_s >= t_stop + 6)
  c(secs_to_blank = if (is.na(i)) NA_real_ else w$t_s[[i]] - t_stop, shown_after_6s = sum(!is.na(after[[cand]])))
}

score <- function(dir, name) {
  lab <- read_csv(file.path(dir, str_c(name, "_lab.csv")), na = "NA", show_col_types = FALSE)
  truth <- read_csv(file.path(dir, str_c(name, "_truth.csv")), show_col_types = FALSE)
  strokes <- read_csv(file.path(dir, str_c(name, "_strokes.csv")), show_col_types = FALSE)
  d <- inner_join(lab, truth, by = "t_s")
  # seconds since the last abrupt change of the nominal rate (or restart after a pause)
  jump <- (abs(d$rate - lag(d$rate, default = 0)) >= 5)
  d$since_jump <- sequence(rle(cumsum(jump))$lengths) - 1
  paddling <- d |> filter(rate > 0, t_s >= 8)
  changes <- truth |> mutate(prev = lag(rate)) |> filter(rate > 0, prev > 0, rate != prev, t_s > 10)
  stops <- truth |> mutate(prev = lag(rate)) |> filter(rate == 0, prev > 0)

  rows <- map(names(candidates), \(cand) {
    v <- paddling[[cand]]
    err <- v - paddling$rate
    rel <- abs(err) / paddling$rate
    tibble(
      algorithm = candidates[[cand]],
      coverage = mean(!is.na(v)),
      mae = mean(abs(err), na.rm = TRUE),
      p90 = quantile(abs(err), 0.9, na.rm = TRUE),
      steady_sd = sd(err[paddling$since_jump >= 12], na.rm = TRUE),
      glitch = mean(rel > glitch_tol, na.rm = TRUE),
      step_s = if (nrow(changes)) mean(pmap_dbl(changes, \(t_s, rate, prev, ...) step_response(d, cand, t_s, rate)), na.rm = TRUE) else NA_real_,
      steps_missed = if (nrow(changes)) sum(is.na(pmap_dbl(changes, \(t_s, rate, prev, ...) step_response(d, cand, t_s, rate)))) else NA_integer_,
      stop_s = if (nrow(stops)) mean(map_dbl(stops$t_s, \(ts) stop_response(d, cand, ts)[["secs_to_blank"]]), na.rm = TRUE) else NA_real_,
      shown_in_pause = if (nrow(stops)) sum(map_dbl(stops$t_s, \(ts) stop_response(d, cand, ts)[["shown_after_6s"]])) else NA_real_
    )
  }) |> list_rbind()
  cat(sprintf("\n== %s (%d true strokes, %d paddling seconds scored)\n", name, nrow(strokes), nrow(paddling)))
  options(tibble.width = Inf)
  print(rows |> mutate(across(c(coverage, glitch), \(x) round(100 * x)), across(c(mae, p90, steady_sd, step_s, stop_s), \(x) round(x, 1))) |> select(-steps_missed))
  invisible(rows)
}

args <- commandArgs(trailingOnly = TRUE)
for (sc in args[-1]) score(args[[1]], sc)
cat("\ncoverage %: paddling seconds with a displayed value; mae/p90: strokes/min error vs the true nominal rate;\n",
    "glitch %: displayed value off by more than 15 %; step_s: seconds until within 10 % after a rate change;\n",
    "steady_sd: sd of the error 12+ s after an abrupt change (jitter of the display);\n",
    "stop_s: seconds until the display blanks after paddling stops; shown_in_pause: seconds still displayed 6+ s into pauses.\n", sep = "")
