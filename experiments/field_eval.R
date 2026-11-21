# Score AcfTracker settings on the field-condition recordings of experiments/gen_field.py,
# replayed through the firmware classes (test/host/acf_replay.cpp, built to .pio/acf_replay).
# The tracker's per-second output stands in for the head unit (the CS300 adds ~1-2 s).
#
# Usage: Rscript experiments/field_eval.R FIELD_DIR [name:key=v,key=v ...]
#   configs default to old / floor22 / stop / new below; each extra argument defines one instead.
suppressMessages(library(tidyverse))
suppressMessages(library(parallel))
args <- commandArgs(trailingOnly = TRUE)
dir <- args[[1]]
replay <- ".pio/acf_replay"
configs <- list(
  old = c("relStop=0", "relStart=0", "rmin=30"),
  floor22 = c("relStop=0", "relStart=0", "rmin=22"),
  stop = c("rmin=30"),
  new = c("rmin=22")
)
if (length(args) > 1) {
  configs <- map(args[-1], \(a) { x <- str_split_1(a, ":"); if (length(x) > 1 && nzchar(x[[2]])) str_split_1(x[[2]], ",") else character() })
  names(configs) <- str_extract(args[-1], "^[^:]+")
}

run <- function(name, args) {
  out <- tempfile(fileext = ".csv")
  system2(replay, args, stdin = file.path(dir, str_c(name, ".csv")), stdout = out, stderr = FALSE)
  d <- read_csv(out, na = "NA", show_col_types = FALSE) |> mutate(t_s = t_s - 1) # row n covers second n-1
  unlink(out)
  truth <- read_csv(file.path(dir, str_c(name, "_truth.csv")), show_col_types = FALSE)
  inner_join(truth, d, by = "t_s", suffix = c("", "_shown")) |> rename(shown = rate_shown)
}

score <- function(d) {
  seg <- cumsum(c(1, abs(diff(d$rate)) >= 3))
  d <- d |> mutate(seg = seg, since = sequence(rle(seg)$lengths) - 1)
  pad <- d |> filter(rate > 0, since >= 15)
  err <- pad$shown - pad$rate
  starts <- d |> filter(rate > 0, since == 0, lag(rate, default = 0) == 0)
  stops <- d |> filter(rate == 0, since == 0, lag(rate, default = 0) > 0)
  first_blank <- \(t0) { w <- d |> filter(t_s >= t0, t_s < t0 + 30); i <- which(is.na(w$shown))[1]; if (is.na(i)) 30 else w$t_s[[i]] - t0 }
  first_shown <- \(t0) { w <- d |> filter(t_s >= t0, t_s < t0 + 40); i <- which(!is.na(w$shown))[1]; if (is.na(i)) 40 else w$t_s[[i]] - t0 }
  rest <- d |> filter(rate == 0, since >= 10, t_s > 20)
  # paddling seconds except the first 15 s after a start from rest (includes rate/amplitude changes)
  run_id <- cumsum(c(1, diff(d$rate > 0) != 0))
  all <- d |> mutate(k = sequence(rle(run_id)$lengths) - 1) |> filter(rate > 0, k >= 15)
  tibble(
    drop = mean(is.na(all$shown)),
    cover = mean(!is.na(pad$shown)),
    mae = mean(abs(err), na.rm = TRUE),
    glitch = mean(abs(err) / pad$rate > 0.15, na.rm = TRUE),
    half = mean(abs(pad$shown - pad$rate / 2) <= 0.12 * pad$rate / 2, na.rm = TRUE),
    start_s = if (nrow(starts)) mean(map_dbl(starts$t_s, first_shown)) else NA_real_,
    stop_s = if (nrow(stops)) mean(map_dbl(stops$t_s, first_blank)) else NA_real_,
    stop_max = if (nrow(stops)) max(map_dbl(stops$t_s, first_blank)) else NA_real_,
    rest_shown = if (nrow(rest)) mean(!is.na(rest$shown)) else NA_real_
  )
}

names <- str_remove(list.files(dir, "_truth\\.csv$"), "_truth\\.csv$")
jobs <- expand_grid(name = names, config = names(configs))
runs <- mclapply(seq_len(nrow(jobs)), \(i) run(jobs$name[[i]], configs[[jobs$config[[i]]]]), mc.cores = 8)
res <- jobs |> mutate(s = map(runs, score)) |> unnest(s) |>
  mutate(scenario = str_remove(name, "^s[0-9]+_"), scenario = str_replace(scenario, "steady[0-9]+", "steady40-60"))

options(tibble.width = Inf, pillar.sigfig = 3)
cat("Mean over seeds. cover/glitch/half/rest_shown in %; seconds for start/stop.\n",
    "drop: paddling seconds (15+ s after a start from rest) left blank;\n",
    "cover: paddling seconds (15+ s into a segment) with a rate shown; glitch: shown rate >15 % off;\n",
    "half: shown rate ~ half the true one; stop_s: seconds from the last stroke to blank (max: worst stop);\n",
    "rest_shown: resting seconds (10+ s into the rest) with a rate shown.\n\n", sep = "")
tab <- res |> group_by(scenario, config) |>
  summarise(across(c(drop, cover, glitch, half, rest_shown), \(v) round(100 * mean(v, na.rm = TRUE))),
            across(c(mae, start_s, stop_s), \(v) round(mean(v, na.rm = TRUE), 1)), stop_max = max(stop_max), .groups = "drop") |>
  mutate(config = factor(config, names(configs))) |> arrange(scenario, config)
print(tab, n = Inf)

# Per true rate on the slow scenario: share of seconds shown within 10 %.
slow <- jobs |> mutate(d = runs) |> filter(str_detect(name, "_slow$")) |> unnest(d) |>
  filter(rate > 0) |> group_by(config, rate) |> filter(row_number() > 15 * n_distinct(name)) |>
  summarise(ok = round(100 * mean(!is.na(shown) & abs(shown - rate) <= 0.1 * rate)), .groups = "drop") |>
  pivot_wider(names_from = rate, values_from = ok, names_prefix = "r")
cat("\nslow: % of seconds within 10 % of the true rate (after 15 s at each rate)\n")
print(slow |> mutate(config = factor(config, names(configs))) |> arrange(config))
