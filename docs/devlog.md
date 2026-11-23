# Development log

Milestone by milestone: what was built, how it was verified, and what went
wrong along the way. Hardware notes and the rail test are in
[hardware.md](hardware.md); the logger and analysis scripts in
[analysis.md](analysis.md).

## Milestones

| # | Env / UF2 | What it does | Status |
|---|---|---|---|
| 1 | `m1_hello` | USB serial + LED blink | ✅ verified 2026-11-17 (serial, both LEDs, button, `dfu` escape) |
| 2 | `m2_accel` | I2C scan, LIS2DH WHO_AM_I, x/y/z at 10 Hz | ✅ verified 2026-11-17 (0x19, 0x33, \|a\| ≈ 0.99 g at rest) |
| 3 | `m3_csc` | BLE CSC sensor, fixed 60 rpm (go/no-go) | ✅ **GO** 2026-11-17: CS300 shows 60 rpm |
| 4 | `m4_logger` | 100 Hz accel over BLE UART (FIFO) + battery lines + R script | ✅ 2026-11-17: Mac and iPhone (Bluefruit Connect), 0 lost, ~100.6 Hz; boat session pending |
| 5 | `m5_stroke` | On-device stroke detector → CSC cadence, GNSS off | replay-tested; bench ✅; **CS300 shows cadence** ✅ 2026-11-19; smoothing added; water pending |
| 5b | `m5_acf` | Same, but the rate comes from a running-autocorrelation tracker; blanks outside 24–110/min (was 30) | flashed 2026-11-19; bench: firmware == Mac replay; real session pending |
| 6 | — | Power management | later |
| — | `docs/junction_box.md` | Sidequest: solar + battery junction box | paper design |
| — | — | Idea: stroke rate as a Meshtastic module ([below](#possible-future-a-meshtastic-module)) | not started |
| T | `t_rail` | Test: what is on the switched 3.3 V rail | ✅ run 2026-11-17: GNSS on the rail, accelerometer not |

### 5 — Stroke detector + cadence (`m5_stroke.uf2`)

- `lib/stroke/stroke_detector.{h,cpp}`: causal port of `analysis/stroke_rate.R`
  (gravity EMA → horizontal part → surge axis tracked by EMA covariance +
  power iteration → 0.5–2 Hz band-pass → adaptive-threshold peaks with a
  minimum gap of ≥ 0.6 s and ≥ 60 % of the recent median interval, capped
  at 1 s; a peak past 0.6 s that is at least 80 % of the recent typical
  peak still counts, so sudden speed-ups don't lock at half rate). Plain
  C++, no Arduino.
- Replay on the Mac (`test/host/stroke_replay.cpp`) of the 45-min OC1
  session: **1833 strokes vs 1828 in R**, 94 % within 0.3 s of an R stroke.
- **Half-rate lock (2026-11-19):** on the CS300 the rate could not get past
  ~50/min when speeding up. After a slower stretch the adaptive minimum gap
  (60 % of the recent interval) rejected every other faster stroke, so the
  detector saw half the real rate and the gap never shrank. Fix: a peak
  past the fixed 0.6 s gap counts if it is ≥ 80 % of the recent median peak
  (split peaks at side switches are weaker). Simulated steps 40, 80, 45, 65,
  90, 40/min: detected 41, 81, 45, 64, 90, 40 (before: 37, 32, 45, 64, 90,
  38). Threshold 0.8 chosen from 0.6–0.9: fewest extra strokes on the water
  session while all steps stay correct. Without the 1 s cap, a few
  early misses inflated the gap and locked it at every other stroke (375
  strokes); the surge axis also settles faster now (running mean until the
  20 s EMA takes over).

  ```sh
  c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp test/host/stroke_replay.cpp -o .pio/stroke_replay
  .pio/stroke_replay < data/<session>_window.csv     # lines seq,t_ms,x_mg,y_mg,z_mg
  ```
- Firmware: each confirmed stroke = one crank revolution (event time = the
  stroke's peak, 1/1024 s); CSC Measurement notified every second, so the
  head unit shows strokes/min and drops to 0 when paddling stops. A stroke
  is confirmed ~0.6–0.9 s after its peak.
- Advertises as **Paddle Stroke** (CSC service + appearance; Nordic UART in
  the scan response); two connections (head unit + phone). The UART carries
  the raw 100 Hz stream as in M4 plus `# stroke n=… seq=… t_ms=…` and
  `# battery` lines, so a phone can record for validation while the CS300
  shows cadence.
- GNSS rail off, blue LED off, green blinks 30 ms per stroke and every
  5 s (heartbeat); battery service reports a real percentage (Meshtastic's
  OCV table).
- **CS300 link fix (2026-11-19):** the first M5 build requested 2M PHY,
  data length and MTU 247 on every connection (as M4 does for phones); the
  CS300 then dropped the link after exactly 30 s (an unanswered GATT
  procedure times out), over and over. Without those requests (as in M3)
  it stays connected (`CS300-xxxxxxx` in the log). Phones still negotiate a
  large MTU themselves. Some connection attempts still fail at first
  (reason 0x3E) before one sticks.
- **Smoothing (2026-11-19):** the head unit shows 60 / (time between the
  last two strokes), so it jumped with every stroke (water session:
  41.9 ± 6.5/min, 24–90). The stroke count stays exact; the reported stroke
  times are spaced at the mean of the last 4 intervals without the
  shortest and longest, pulled 5 % per stroke toward real time, restarting
  after a pause (> 2.5 s). Replayed on the water session: 41.2 ± 3.6/min
  (29–58). A 40 → 55/min change shows within 4 strokes. (8 intervals gave
  ± 2.8 but took 7 strokes and felt too slow on the CS300.)

### 5b — Autocorrelation tracker (`m5_acf.uf2`)

Replaces the peak accept/reject logic of M5 (which `m5_stroke` keeps as the fallback)
with a continuous period estimate, after the Mac lab in `experiments/` showed it is far
steadier. `lib/stroke/acf_tracker.{h,cpp}` (plain float C++, ~2k multiply-adds/s) takes
the band-passed surge from `StrokeDetector`, keeps a recursive autocorrelation, picks the
period every 0.2 s (octave check, parabola, median + EMA) and blanks rhythms outside
30–110 strokes/min. Strokes sent to the head unit are the integer crossings of the
integrated phase of that rate, so they are evenly spaced; the stroke *count* is only
meaningful as a cadence.

- Real OC1 session (45 min, Mac lab): jitter 1.3 vs 3.5 strokes/min for the peak
  logic, 0.7 % vs 9.2 % of seconds off by more than 15 %. Settings tuned on separate
  train / validation / fresh synthetic sets and two halves of the real session
  (`experiments/tune.R`); out-of-range blanking 92–100 % for 115–150/min and 25–28/min,
  96–100 % correct for 32–108/min (`experiments/range_eval.R`, synthetic).
- Known limits: starts ~10 s after paddling begins, keeps a stale rhythm 4–5 s after a
  stop, slow to follow a doubling of the rate (7 s); cannot tell wave rhythm inside the
  range from paddling; rates around 15–20/min are not reliably caught.
- **Second water session (OC1, 2026-11-21, CS300 FIT vs watch; no raw Tag data).** 12 s
  windows while paddling steadily: bias −0.05, MAE 2.35 spm, 76 % within ±3. But after
  every stop the CS300 kept the old rate 15–25 s (hull motion after a stop stayed above
  `gate`, and the decaying correlation memory kept the rhythm), and slow paddling at
  31–34/min dropped out when estimates dipped under the 30/min floor.
- **Fix (2026-11-21):** stop relative to the paddler's own level: when the 1 s rms stays
  below 0.45 × the paddling rms (8 s level) for 1.6 s, the rhythm is dropped and the
  correlation memory cleared; a restart then needs 0.5 × that level (fading over 20 s).
  Floor lowered to 24/min. Checked with `experiments/gen_field.py` (stops in seas of
  10–55 mg rms, swell at 45/min, slow 20–34/min, sprint, easing off) scored by
  `experiments/field_eval.R` (replay of the firmware classes, old vs new settings):
  stop → blank 19 → 4–8 s where the sea after a stop is < ~0.45 × paddling, no change in
  rougher sea (17–19 s); 25/min shown 0 → 86 %, 28/min 4 → 98 %; glitches +1–3 points in
  rough sea; no blanks when the stroke amplitude halves. Real 45 min of 2026-11-18:
  identical to before (0 extra blank seconds; 1.6 s confirmation chosen because 0.6 s
  blanked a 6 s stretch of light strokes there). Rest shown in the simulated sea stays
  high: the simulated sea is more rhythmic than the water (the CS300 stayed at 0 during
  the real rests once blank).
- Bench after the fix (2026-11-21, hand sliding to a click track, USB serial;
  `experiments/bench/{protocol,capture}.pl`, compared with `experiments/bench/compare.R`;
  data `data/bench_m5acf_v2_*`): device == replay (0.3 spm). 45/min steady 44–45; clean
  stop blank in 2 s (old 3 s); 26/min shown 25–26 for the whole minute (old: blank);
  32/min 31–32. Stop followed by hand wobbling blanked in 3 s (old kept 45 for 6 s), but
  the wobble itself (~100/min) was then tracked by both: the bench cannot imitate sea
  motion.
- Replay on the Mac (same classes as the firmware, float):
  `c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp lib/stroke/acf_tracker.cpp test/host/acf_replay.cpp -o .pio/acf_replay`
  then `.pio/acf_replay [key=value ...] < data/session_window.csv` (args override `AcfParams`). Against the double-precision lab it
  agrees to 0.7 strokes/min on the real session (two seconds at a rate jump differ by
  more) and within one event in the count.
- Bench on the Tag (hand sliding, 3 min): device and Mac replay of the recorded raw
  stream agree (validity identical in 185 readouts, median difference 0.1 strokes/min).
  Moving at ~157/min (spectrum of the raw surge) was blanked after ~6 s of showing a wrong
  60. Hand sliding has strong harmonics, so its true cycle rate is ambiguous (at 145-160 s
  both tracker and peak logic said 48/min, the spectrum's strongest line was ~100/min):
  accuracy needs real paddling with counted strokes.
- UART log lines for checking a session: `# rate t_ms=… acf=… valid=… revs=…` once a
  second (what the tracker believes), `# acf n=… t_ms=…` per stroke sent to the head
  unit, `# stroke …` for the old peak logic (logged only), `# battery …`.

### 1 — Hello world (`m1_hello.uf2`)

Expect `Paddle Stroke: hello from the WisMesh Tag`, then `tick N  uptime … ms`
once per second; green and blue LEDs alternate every second.
Confirms toolchain, UF2 layout, USB serial and LED pins.

### 2 — Accelerometer (`m2_accel.uf2`)

Expect an I2C scan listing `0x18` or `0x19` (maybe other devices), then
`LIS2DH at 0x1?, WHO_AM_I = 0x33`, then `x_mg,y_mg,z_mg` lines at 10 Hz.
Lying flat and still: one axis ≈ ±1000 mg, the others ≈ 0. Rotate the Tag:
the ~1000 mg moves to another axis. Green LED toggles per sample; fast
blinking + "NOT found" means the accelerometer wasn't detected — send me the
scan output.

Settings: ±4 g, high-resolution 12-bit (2 mg/digit), block data update.

### 3 — BLE cadence sensor, fixed 60 rpm (`m3_csc.uf2`)

- Advertises as **Paddle Stroke**, appearance 0x0483 (cadence sensor),
  service 0x1816.
- CSC Measurement 0x2A5B (notify): `02 RR RR TT TT` — flags 0x02, uint16
  crank revolutions, uint16 last event time (1/1024 s), little-endian.
  +1 rev and +1024 time units every second.
- CSC Feature 0x2A5C (read): `02 00`. Sensor Location 0x2A5D (read): `00`.
- Also Device Information and Battery (fixed 100 %) services.
- Blue LED blinks while advertising, solid when connected; green flashes
  once per "revolution". Serial prints `revs N  event_time T`.

Mac check (Python `bleak` in `.venv`): `.venv/bin/python scripts/csc_check.py`
scans, reads CSC Feature and decodes 5 notifications into rpm.

Test with nRF Connect (iPhone): scan → Paddle Stroke shows the CSC service
in the advertisement → connect → Cycling Speed and Cadence → enable
notifications on CSC Measurement: a 5-byte value every second, revs and
time increasing (time by 0x0400). Read CSC Feature = `0x0002`. Disconnect,
then on the CS300 add a cadence sensor: it should find "Paddle Stroke" and show
**60 rpm**.

### 4 — 100 Hz logger (`m4_logger.uf2`)

See [analysis.md](analysis.md#100-hz-logger-m4_loggeruf2).

## Possible future: a Meshtastic module

Idea, not started (2026-11-23). Instead of replacing Meshtastic, add the
stroke detector and tracker (`lib/stroke`, plain C++) as a module in a
Meshtastic fork, plus a Cycling Speed & Cadence GATT service, so the Tag
stays a tracker and mesh node while the head unit shows cadence.

What it would add:
- Position over the mesh while paddling (safety offshore, escort boat).
- Stroke rate shared over the mesh to a coach or escort, not only to the
  CS300.
- One firmware for both jobs; no reflashing.

What it would cost:
- A fork of a large, fast-moving codebase, rebased on every Meshtastic
  release; a CSC service is unlikely to be accepted upstream.
- The CS300 shares the BLE radio with Meshtastic's phone connection; M5
  showed the CS300 is picky about connection parameters (the 30 s drops).
- GPS and LoRa stay on: no milestone-6 power savings.

To check first (unverified assumptions): Meshtastic's nRF52 build uses
Bluefruit, as we do, and already reads the accelerometer for motion
features; how hard it is to add a second BLE service next to Meshtastic's
own.
