# Rscript test/r/test_read_accel.R
# read_accel() on a file written by the tagvaa recorder app (ios/).
Sys.setenv(TZ = "UTC") # so the time zone must come from the file, not this machine
suppressMessages(source("analysis/read_accel.R"))

fixture <- "test/r/fixtures/recorder_sample.csv"
path <- tempfile(fileext = ".csv")
invisible(file.copy(fixture, path))
Sys.setFileTime(path, as.POSIXct("2020-01-01 12:00:00", tz = "UTC")) # the date must not come from here

acc <- suppressMessages(read_accel(path))

stopifnot(
  nrow(acc) == 30,
  identical(acc$seq, as.numeric(0:29)),
  "time" %in% names(acc),
  attr(acc$time, "tzone") == "America/Bahia",
  as.Date(min(acc$time), tz = "America/Bahia") == as.Date("2026-11-25"),
  abs(as.numeric(difftime(min(acc$time), as.POSIXct("2026-11-25 06:12:04", tz = "America/Bahia"), units = "secs"))) < 1
)

info <- read_stream_lines(path)$info
stopifnot(nrow(info) == 2, startsWith(info$text[1], "start date=2026-11-25"))

# A Bluefruit export still reads, with no INFO rows.
blue <- read_stream_lines(fixture_blue <- {
  p <- tempfile(fileext = ".csv")
  writeLines(c("Timestamp,Mode,Data", '10:00:00.000,RX,"1,10,8,-56,992"', '10:00:00.010,RX,"2,20,8,-56,992"'), p)
  p
})
stopifnot(nrow(blue$info) == 0, length(grep(data_pattern, blue$lines)) == 2)

cat("read_accel tests passed\n")
