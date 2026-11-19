# Score rate_lab output on a real session against the watch.
# Usage: Rscript experiments/evaluate_real.R lab.csv watch.fit "2026-11-18 18:41:38" [tz]
# The third argument is the wall-clock time of the first sample fed to rate_lab.
suppressMessages(library(tidyverse))
suppressMessages(library(slider))
local({
  here <- dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE)))
  assign("project_dir", normalizePath(file.path(here, "..")), envir = globalenv())
})
source(file.path(project_dir, "analysis", "stroke_rate.R"))

args <- commandArgs(trailingOnly = TRUE)
tz <- if (length(args) >= 4) args[[4]] else "America/Bahia"
lab <- read_csv(args[[1]], na = "NA", show_col_types = FALSE)
ref <- read_reference(args[[2]]) |> mutate(time = with_tz(time, tz))
t0 <- as.POSIXct(args[[3]], tz = tz)
lab <- lab |> mutate(time = t0 + t_s)

cands <- c("B", "Bn", "Z", "A", "D")
steady <- lab |> filter(t_s > 30)
cat(sprintf("%d s of recording, %.0f s scored\n\n", nrow(lab), nrow(steady)))

jit <- map(cands, \(cand) {
  v <- steady[[cand]]
  med <- slide_dbl(v, \(x) median(x, na.rm = TRUE), .before = 30, .after = 30)
  dev <- v - med
  tibble(
    algorithm = cand,
    coverage = mean(!is.na(v)),
    mean_rate = mean(v, na.rm = TRUE),
    jitter_sd = sd(dev, na.rm = TRUE),
    glitch_15 = mean(abs(dev) / med > 0.15, na.rm = TRUE),
    glitch_30 = mean(abs(dev) / med > 0.30, na.rm = TRUE),
    step_1s = median(abs(diff(v)), na.rm = TRUE)
  )
}) |> list_rbind()
cat("short-term jitter (deviation from the centred 61 s median of the same series):\n")
print(jit |> mutate(across(c(coverage, glitch_15, glitch_30), \(x) round(100 * x, 1)), across(where(is.double), \(x) round(x, 2))), width = 200)

pm <- lab |>
  mutate(min = floor_date(time, "minute")) |>
  group_by(min) |>
  summarise(across(all_of(cands), \(v) mean(v, na.rm = TRUE)), n = n()) |>
  filter(n >= 55)
rm <- ref |>
  mutate(min = floor_date(time, "minute")) |>
  group_by(min) |>
  summarise(watch = mean(ref_spm))
j <- inner_join(pm, rm, by = "min")
cat(sprintf("\nper-minute agreement with the watch (%d minutes):\n", nrow(j)))
print(map(cands, \(cand) tibble(algorithm = cand, bias = mean(j[[cand]] - j$watch, na.rm = TRUE), mae = mean(abs(j[[cand]] - j$watch), na.rm = TRUE), r = cor(j[[cand]], j$watch, use = "complete"))) |> list_rbind() |> mutate(across(where(is.double), \(x) round(x, 2))))
cat(sprintf("watch: mean %.1f, sd of minute means %.2f\n", mean(j$watch), sd(j$watch)))
