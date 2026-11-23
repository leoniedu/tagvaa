# Compare a bench recording (device "# rate" lines) with the Mac replay of its raw stream,
# new settings vs old (relStop=0 relStart=0 rmin=30), per phase of the click-track protocol.
# Usage: Rscript experiments/bench/compare.R data/bench_m5acf_v2   (needs .pio/acf_replay)
suppressPackageStartupMessages(library(tidyverse))
P <- commandArgs(TRUE)[1]
f <- \(x) str_c(P, "_", x)
raw <- read_csv(f("raw.csv"), col_names = c("seq","t_ms","x","y","z"), show_col_types = FALSE)
rl <- read_lines(f("serial.txt")) |> str_subset("# rate")
dev <- tibble(host = as.numeric(str_extract(rl, "^[0-9]+")), t_ms = as.numeric(str_match(rl, "t_ms=([0-9]+)")[,2]),
  acf = as.numeric(str_match(rl, "acf=([0-9.]+)")[,2]), valid = as.integer(str_match(rl, "valid=([01])")[,2]))
off <- median(dev$host - dev$t_ms)
ev <- read_tsv(f("events.tsv"), col_names = c("host","phase","rate"), show_col_types = FALSE) |> mutate(t_ms = host - off)
t0 <- raw$t_ms[1]
rep <- function(args) {
  out <- tempfile(fileext = ".csv")
  system2(".pio/acf_replay", args, stdin = f("raw.csv"), stdout = out, stderr = FALSE)
  read_csv(out, na = "NA", show_col_types = FALSE) |> mutate(t_ms = t0 + t_s * 1000)
}
new <- rep(character()); old <- rep(c("relStop=0", "relStart=0", "rmin=30"))
at <- \(d, t) { i <- findInterval(t, d$t_ms); if (i < 1) NA else d$rate[i] }
g <- dev |> mutate(dev = ifelse(valid == 1, acf, NA), new = map_dbl(t_ms, \(t) at(new, t)), old = map_dbl(t_ms, \(t) at(old, t)),
  phase = ev$phase[pmax(1, findInterval(t_ms, ev$t_ms))], since = round((t_ms - ev$t_ms[pmax(1, findInterval(t_ms, ev$t_ms))]) / 1000))
g <- g |> filter(t_ms >= ev$t_ms[1], t_ms < tail(ev$t_ms, 1))
both <- g |> filter(!is.na(dev) | !is.na(new))
cat(sprintf("device vs new replay: validity agrees %.0f%% of %d s; median |diff| %.2f\n", 100*mean(is.na(g$dev) == is.na(g$new)), nrow(g), median(abs(g$dev - g$new), na.rm = TRUE)))
fmt <- \(v) ifelse(is.na(v), "  -", sprintf("%3.0f", v))
for (p in unique(g$phase)) { x <- g |> filter(phase == p)
  cat(sprintf("\n%-8s dev:%s\n%-8s new:%s\n%-8s old:%s\n", p, paste(fmt(x$dev), collapse=""), "", paste(fmt(x$new), collapse=""), "", paste(fmt(x$old), collapse=""))) }
