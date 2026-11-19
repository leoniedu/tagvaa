# Tune the parameters of tracker A (rate_lab.cpp) with a train / validation split.
#
#   train       : synthetic seeds 101-105 (prefix tr_) + first 24 min of the real session
#   validation  : synthetic seeds 201-205 (prefix va_) + the remaining 21 min (never used to tune)
#
# Usage: Rscript experiments/tune.R SYNTH_DIR real_window.csv R_strokes.csv [mode]
#   mode "sweep"  : one-at-a-time sweeps around the defaults (train)
#   mode "search" : random search on train, best candidates re-scored on validation
suppressMessages(library(tidyverse))
suppressMessages(library(slider))
suppressMessages(library(parallel))
args <- commandArgs(trailingOnly = TRUE)
dirS <- args[[1]]
real_csv <- args[[2]]
r_strokes <- read_csv(args[[3]], show_col_types = FALSE)
mode <- if (length(args) >= 4) args[[4]] else "sweep"
lab <- ".pio/rate_lab"
cores <- max(1, min(8, detectCores() - 1))
SPLIT <- 144000 # samples; 24 min, so both halves start on a minute boundary

# --- data -------------------------------------------------------------------------
all_lines <- read_lines(real_csv)
s0 <- as.numeric(str_extract(all_lines[[1]], "^[0-9]+"))
write_lines(all_lines[seq_len(SPLIT)], ".pio/real_train.csv")
write_lines(all_lines[-seq_len(SPLIT)], ".pio/real_val.csv")
ref_per_min <- function(first_sample, n_samples) {
  r_strokes |>
    mutate(m = (seq - s0 - first_sample) %/% 6000) |>
    filter(m >= 0, m < n_samples %/% 6000) |>
    count(m, name = "ref")
}
ref_train <- ref_per_min(0, SPLIT)
ref_val <- ref_per_min(SPLIT, length(all_lines) - SPLIT)

run_lab <- function(csv, par, fast = TRUE) {
  out <- tempfile(fileext = ".csv")
  a <- c(if (fast) "fast=1", imap_chr(par, \(v, k) str_c(k, "=", v)))
  system2(lab, a, stdin = csv, stdout = out, stderr = FALSE)
  d <- read_csv(out, na = "NA", show_col_types = FALSE)
  unlink(out)
  d
}

# --- metrics ----------------------------------------------------------------------
resp_time <- function(d, t_change, new) {
  w <- d |> filter(t_s >= t_change, t_s < t_change + 25)
  ok <- !is.na(w$disp) & abs(w$disp - new) <= 0.1 * new
  i <- which(ok & lead(ok, 1, FALSE) & lead(ok, 2, FALSE))[1]
  if (is.na(i)) 25 else w$t_s[[i]] - t_change
}

synth_one <- function(name, d_lab) {
  truth <- read_csv(file.path(dirS, str_c(name, "_truth.csv")), show_col_types = FALSE)
  strokes <- read_csv(file.path(dirS, str_c(name, "_strokes.csv")), show_col_types = FALSE)$t_s
  d <- inner_join(d_lab, truth, by = "t_s")
  jump <- abs(d$rate - lag(d$rate, default = 0)) >= 5
  d$since <- sequence(rle(cumsum(jump))$lengths) - 1
  p <- d |> filter(rate > 0, t_s >= 12)
  err <- p$disp - p$rate
  changes <- d |> mutate(prev = lag(rate)) |> filter(rate > 0, prev > 0, abs(rate - prev) >= 5, t_s > 10)
  stops <- d |> mutate(prev = lag(rate)) |> filter(rate == 0, prev > 0)
  first_stroke <- min(strokes)
  tibble(
    cover = mean(!is.na(p$disp)),
    mae = mean(abs(err), na.rm = TRUE),
    steady_sd = sd(err[p$since >= 12], na.rm = TRUE),
    glitch = mean(abs(err) / p$rate > 0.15, na.rm = TRUE),
    step_s = if (nrow(changes)) mean(pmap_dbl(changes, \(t_s, rate, ...) resp_time(d, t_s, rate))) else NA_real_,
    stop_s = if (nrow(stops)) mean(map_dbl(stops$t_s, \(ts) { w <- d |> filter(t_s >= ts, t_s < ts + 15); i <- which(is.na(w$disp))[1]; if (is.na(i)) 15 else w$t_s[[i]] - ts })) else NA_real_,
    tail_s = if (nrow(stops) && "int" %in% names(d) && any(!is.na(d$int))) mean(map_dbl(stops$t_s, \(ts) { last <- max(strokes[strokes < ts + 1]); w <- d |> filter(t_s > last, t_s < last + 15); i <- which(is.na(w$int))[1]; if (is.na(i)) 15 else w$t_s[[i]] - last })) else NA_real_,
    start_s = (d |> filter(!is.na(disp)) |> pull(t_s) |> first()) - first_stroke
  )
}

synth_metrics <- function(prefix, runner) {
  names <- str_c(prefix, c("steps", "steps_chop", "ramps", "steady_chop", "gentle"))
  per <- map(names, \(n) synth_one(n, runner(file.path(dirS, str_c(n, ".csv")))))
  names(per) <- c("steps", "steps_chop", "ramps", "steady_chop", "gentle")
  tibble(
    cover = min(map_dbl(per, "cover")),
    mae = mean(map_dbl(per, "mae")),
    steady_sd = mean(map_dbl(per, "steady_sd")),
    step_s = mean(c(per$steps$step_s, per$steps_chop$step_s)),
    stop_s = mean(c(per$steps$stop_s, per$ramps$stop_s, per$gentle$stop_s)),
    tail_s = mean(c(per$steps$tail_s, per$ramps$tail_s, per$gentle$tail_s)),
    start_s = mean(c(per$steps$start_s, per$gentle$start_s)),
    chop_glitch = per$steady_chop$glitch,
    chop_shown = NA_real_
  )
}

real_metrics <- function(d_lab, ref) {
  d <- d_lab |> filter(t_s > 30)
  v <- d$disp
  med <- slide_dbl(v, \(x) median(x, na.rm = TRUE), .before = 30, .after = 30)
  lvl <- d |>
    mutate(m = t_s %/% 60) |>
    group_by(m) |>
    summarise(mean_disp = mean(disp, na.rm = TRUE), n = sum(!is.na(disp))) |>
    filter(n >= 50) |>
    inner_join(ref, by = "m")
  tibble(
    real_cov = mean(!is.na(v)),
    real_sd = sd(v - med, na.rm = TRUE),
    real_glitch = mean(abs(v - med) / med > 0.15, na.rm = TRUE),
    level_err = mean(abs(lvl$mean_disp - lvl$ref)),
    level_bias = mean(lvl$mean_disp - lvl$ref)
  )
}

score <- function(m) {
  m$J <- with(m, 1.0 * steady_sd + 0.5 * mae + 0.4 * step_s + 0.25 * stop_s + 0.15 * start_s + 15 * chop_glitch +
    0.8 * real_sd + 15 * real_glitch + 1.0 * level_err + 10 * (1 - pmin(cover, real_cov)))
  m
}

eval_cfg <- function(par, set = c("train", "val")) {
  set <- match.arg(set)
  prefix <- if (set == "train") "tr_" else "va_"
  half <- if (set == "train") ".pio/real_train.csv" else ".pio/real_val.csv"
  ref <- if (set == "train") ref_train else ref_val
  sy <- synth_metrics(prefix, \(f) run_lab(f, par) |> transmute(t_s, disp = A, int = Aint))
  rl <- real_metrics(run_lab(half, par) |> transmute(t_s, disp = A), ref)
  score(bind_cols(sy, rl))
}

# baseline B (the algorithm on the Tag), same metrics
eval_B <- function(set) {
  prefix <- if (set == "train") "tr_" else "va_"
  half <- if (set == "train") ".pio/real_train.csv" else ".pio/real_val.csv"
  ref <- if (set == "train") ref_train else ref_val
  sy <- synth_metrics(prefix, \(f) run_lab(f, list(), fast = FALSE) |> transmute(t_s, disp = B, int = NA_real_))
  rl <- real_metrics(run_lab(half, list(), fast = FALSE) |> transmute(t_s, disp = B), ref)
  score(bind_cols(sy, rl))
}


# --- out-of-range detection bench (constant rates, clean + chop) ---------------------------
range_rates <- c(15, 20, 25, 28, 32, 35, 45, 60, 80, 100, 108, 115, 125, 135, 150, 180)
range_one <- function(prefix, kind, r, par) {
  d <- run_lab(file.path(dirS, str_c(prefix, kind, r, ".csv")), par) |> filter(t_s >= 25)
  tibble(rate = r, correct = mean(!is.na(d$A) & abs(d$A - r) <= 0.1 * r), blank = mean(is.na(d$A)))
}
range_metrics <- function(prefix, par) {
  res <- expand_grid(kind = c("clean", "chop"), r = range_rates) |> pmap(\(kind, r) range_one(prefix, kind, r, par)) |> list_rbind()
  inside <- res |> filter(rate >= 32, rate <= 105)
  outside <- res |> filter(rate <= 26 | rate >= 125)
  tibble(inside_correct = mean(inside$correct), inside_blank = mean(inside$blank), oob_blank = mean(outside$blank))
}
# priorities: the right number while paddling, correct blanking; start, stop and response time barely matter
score2 <- function(m) {
  m$J2 <- with(m, 1.0 * steady_sd + 1.0 * mae + 0.1 * step_s + 15 * chop_glitch + 1.0 * real_sd + 15 * real_glitch +
    1.0 * level_err + 10 * (1 - pmin(cover, real_cov)) + 10 * (1 - inside_correct) + 6 * (1 - oob_blank))
  m
}
eval_cfg2 <- function(par, set) {
  prefix <- if (set == "train") "rt_" else "rv_"
  score2(bind_cols(eval_cfg(par, set), range_metrics(prefix, par)))
}
cols2 <- c("J2", "steady_sd", "mae", "step_s", "chop_glitch", "real_sd", "real_glitch", "level_err", "inside_correct", "inside_blank", "oob_blank")

show <- function(x) {
  options(tibble.width = Inf, pillar.sigfig = 3)
  print(x |> mutate(across(where(is.double), \(v) round(v, 2))))
}
cols <- c("J", "steady_sd", "mae", "step_s", "stop_s", "tail_s", "start_s", "chop_glitch", "real_sd", "real_glitch", "level_err", "level_bias")

grids <- list(
  tau = c(1.8, 2, 2.5, 3, 3.5, 4),
  alpha = c(0.1, 0.15, 0.2, 0.3, 0.4, 0.6),
  minRho = c(0.1, 0.2, 0.3, 0.4, 0.5),
  oct = c(0.6, 0.7, 0.8, 0.9, 0.95),
  hold = c(0.4, 1, 2, 3, 4),
  gate = c(0.008, 0.01, 0.012, 0.015, 0.018),
  esTau = c(0.4, 0.6, 1, 1.5),
  medN = c(1, 3, 5),
  estEvery = c(3, 5, 8, 12)
)

if (mode == "fresh") {
  # synthetic-only score on a third, fresh seed set (te_ / rs_): the real session is not re-used
  cfgs <- list(
    defaults = list(),
    id90 = list(tau = 3.39, alpha = 0.29, minRho = 0.31, oct = 0.66, inFrac = 0.52, oobOct = 0.73, outN = 2, hold = 3.22, gate = 0.012, medN = 5, estEvery = 3),
    id36 = list(tau = 3.52, alpha = 0.35, minRho = 0.36, oct = 0.64, inFrac = 0.49, oobOct = 0.76, outN = 2, hold = 2.86, gate = 0.012, medN = 3, estEvery = 5),
    consensus = list(tau = 3.4, alpha = 0.3, minRho = 0.33, oct = 0.65, inFrac = 0.5, oobOct = 0.75, outN = 2, hold = 3, gate = 0.012, medN = 3, estEvery = 5)
  )
  rows <- map2(names(cfgs), cfgs, \(nm, par) {
    sy <- synth_metrics("te_", \(f) run_lab(f, par) |> transmute(t_s, disp = A, int = Aint))
    bind_cols(tibble(config = nm), sy |> select(steady_sd, mae, step_s, chop_glitch, cover), range_metrics("rs_", par))
  }) |> list_rbind()
  rows$J2syn <- with(rows, 1.0 * steady_sd + 1.0 * mae + 0.1 * step_s + 15 * chop_glitch + 10 * (1 - cover) + 10 * (1 - inside_correct) + 6 * (1 - oob_blank))
  show(rows |> arrange(J2syn))
} else if (mode == "search2") {
  set.seed(7)
  n <- as.integer(Sys.getenv("N_SEARCH", "200"))
  keys <- c("tau", "alpha", "minRho", "oct", "inFrac", "oobOct", "outN", "hold", "gate", "medN", "estEvery")
  cand <- tibble(
    tau = runif(n, 2, 6), alpha = runif(n, 0.05, 0.4), minRho = runif(n, 0.2, 0.5), oct = runif(n, 0.6, 0.9),
    inFrac = runif(n, 0.3, 0.6), oobOct = runif(n, 0.5, 0.8), outN = sample(2:5, n, TRUE), hold = runif(n, 1, 4),
    gate = runif(n, 0.008, 0.016), medN = sample(c(3, 5), n, TRUE), estEvery = sample(c(3, 5, 8), n, TRUE)
  ) |> mutate(across(c(tau, alpha, minRho, oct, inFrac, oobOct, hold, gate), \(v) round(v, 3)))
  cand <- bind_rows(tibble(tau = 2.5, alpha = 0.2, minRho = 0.3, oct = 0.8, inFrac = 0.5, oobOct = 0.6, outN = 3, hold = 3, gate = 0.012, medN = 3, estEvery = 5), cand)
  res <- mclapply(seq_len(nrow(cand)), \(i) bind_cols(cand[i, ], eval_cfg2(as.list(cand[i, ]), "train") |> select(all_of(cols2))), mc.cores = cores) |> list_rbind()
  res <- res |> mutate(id = row_number()) |> arrange(J2)
  cat("top 6 on TRAIN:\n"); show(head(res, 6) |> select(id, all_of(keys), all_of(cols2)))
  cat(sprintf("\ncurrent defaults: train rank %d of %d (J2 %.2f)\n", which(res$id == 1), nrow(res), res$J2[res$id == 1]))
  top <- head(res, 4)
  val <- map(seq_len(nrow(top)), \(i) bind_cols(top[i, c("id", keys)], eval_cfg2(as.list(top[i, keys]), "val") |> select(all_of(cols2)))) |> list_rbind()
  dv <- bind_cols(tibble(id = 1), cand[1, keys], eval_cfg2(list(), "val") |> select(all_of(cols2)))
  cat("\nVALIDATION (never used to tune): current defaults (id 1) and the best train configs:\n")
  show(bind_rows(dv, val) |> select(id, all_of(keys), all_of(cols2)))
  write_csv(res, ".pio/tune2_train.csv")
} else if (mode == "check") {
  cfgs <- list(
    defaults = list(),
    consensus = list(tau = 3.4, alpha = 0.3, minRho = 0.33, oct = 0.65, inFrac = 0.5, oobOct = 0.75, outN = 2, hold = 3, gate = 0.012, medN = 3, estEvery = 5)
  )
  rows <- map2(names(cfgs), cfgs, \(nm, par) bind_rows(
    bind_cols(tibble(config = nm, set = "train"), eval_cfg(par, "train") |> select(all_of(cols))),
    bind_cols(tibble(config = nm, set = "val"), eval_cfg(par, "val") |> select(all_of(cols)))
  )) |> list_rbind()
  show(rows |> arrange(set, J))
} else if (mode == "sweep") {
  cat("baseline B (on the Tag), train:\n")
  show(eval_B("train") |> select(all_of(cols)))
  base <- eval_cfg(list(), "train")
  cat("\ncurrent defaults of A, train:\n")
  show(base |> select(all_of(cols)))
  for (k in names(grids)) {
    rows <- mclapply(grids[[k]], \(v) bind_cols(tibble(!!k := v), eval_cfg(setNames(list(v), k), "train") |> select(all_of(cols))), mc.cores = cores) |> list_rbind()
    cat(sprintf("\n-- %s --\n", k))
    show(rows)
  }
} else {
  set.seed(1)
  n <- as.integer(Sys.getenv("N_SEARCH", "150"))
  draw <- \(...) tibble(
    tau = runif(n, 1.8, 4), alpha = runif(n, 0.1, 0.5), minRho = runif(n, 0.1, 0.5), oct = runif(n, 0.6, 0.95),
    hold = runif(n, 0.4, 4), gate = runif(n, 0.008, 0.018), esTau = runif(n, 0.4, 1.5),
    medN = sample(c(1, 3, 5), n, TRUE), estEvery = sample(c(3, 5, 8), n, TRUE)
  )
  cand <- draw() |> mutate(across(c(tau, alpha, minRho, oct, hold, gate, esTau), \(v) round(v, 3)))
  cand <- bind_rows(tibble(tau = 2.5, alpha = 0.2, minRho = 0.3, oct = 0.8, hold = 3, gate = 0.012, esTau = 1, medN = 3, estEvery = 5), cand)
  res <- mclapply(seq_len(nrow(cand)), \(i) bind_cols(cand[i, ], eval_cfg(as.list(cand[i, ]), "train") |> select(all_of(cols))), mc.cores = cores) |> list_rbind()
  res <- res |> mutate(id = row_number()) |> arrange(J)
  cat("top 8 on TRAIN (row 1 of the table is the default config's rank marked by id == 1):\n")
  show(head(res, 8))
  cat(sprintf("\ndefault config: id 1, train rank %d of %d, J = %.2f\n", which(res$id == 1), nrow(res), res$J[res$id == 1]))
  top <- head(res, 5)
  val <- map(seq_len(nrow(top)), \(i) bind_cols(top[i, c("id", "tau", "alpha", "minRho", "oct", "hold", "gate", "esTau", "medN", "estEvery")], eval_cfg(as.list(top[i, c("tau", "alpha", "minRho", "oct", "hold", "gate", "esTau", "medN", "estEvery")]), "val") |> select(all_of(cols)))) |> list_rbind()
  dv <- bind_cols(tibble(id = 1), eval_cfg(list(), "val") |> select(all_of(cols)))
  bv <- bind_cols(tibble(id = 0), eval_B("val") |> select(all_of(cols)))
  cat("\nVALIDATION (data never used to tune): B (id 0), default (id 1), top-5 train configs:\n")
  show(bind_rows(bv, dv, val) |> select(id, any_of(c("tau", "alpha", "minRho", "oct", "hold", "gate", "esTau", "medN", "estEvery")), all_of(cols)))
  write_csv(res, ".pio/tune_train.csv")
}
