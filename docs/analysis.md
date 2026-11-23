# Recording and analysing sessions

## 100 Hz logger (`m4_logger.uf2`)

- Advertises as **Paddle Logger** with the Nordic UART Service.
- LIS2DH at 100 Hz, ±4 g, FIFO in stream mode; the MCU drains it every 50 ms.
- **Resolution: 8 mg steps.** HR mode is enabled, but the LIS2DH FIFO only
  keeps 10 bits per axis (measured: every value a multiple of 8 mg, vs 2 mg
  steps in M2 without FIFO). Noise at rest is ~4 mg sd, so the extra bits
  would mostly be noise; strokes are expected in the 50–300 mg range.
- Streaming starts when the phone subscribes to UART TX (notifications).
  Output, also mirrored to USB serial:

  ```
  # Paddle Logger, 100 Hz, +-4 g, uptime 12345 ms
  seq,t_ms,x_mg,y_mg,z_mg
  0,12350,-12,8,1004
  ```

  `seq` is a gap-free sample counter (use it for timing; gaps = lost data),
  `# battery t_ms=… mv=…` lines carry the Tag battery voltage (in each
  header and once a minute; `read_battery()` in R extracts them),
  `t_ms` the device uptime (for aligning with other recordings). `#` lines
  are comments, including `# FIFO overrun …`.
- Requests MTU 247, 2M PHY and a 15 ms connection interval.
- Accepts **two connections** and keeps advertising while a slot is free:
  a device that auto-reconnects to the Tag's address (seen once right after
  boot, probably a phone or the CS300 paired as "OC6 Stroke") can't lock
  out the recorder. Each subscriber gets its own header; USB serial logs
  `# BLE connected [n] <peer>` / `# streaming to [n]`.
- Phone recording (verified 2026-11-17, iPhone): **Bluefruit Connect** →
  connect (the phone may show the Tag's old Meshtastic name, e.g.
  `Name_xxxx`; if connecting fails, Settings → Bluetooth → Forget This
  Device) → UART → record → export as CSV/text. The export is
  `Timestamp,Mode,Data` with one BLE packet per row; `read_accel()` detects
  it and rejoins lines split across packets. First test: 94.5 s, 0 lost,
  100.61 Hz.
- From the Mac over BLE: `.venv/bin/python scripts/ble_log.py data/session.csv 60`
  (finds the Tag by name or by the UART service, since macOS may show a
  cached old name).
  Over USB: `.venv/bin/pio device monitor --raw --quiet | tee data/session.csv`.
  `data/` is not committed.

## Analysis

```sh
Rscript analysis/read_accel.R data/session.csv          # axes + magnitude plot
Rscript analysis/stroke_rate.R data/session.csv [watch.tcx|.fit|.csv] [YYYY-MM-DD]
```

`read_accel.R` skips non-data lines, rejoins lines split across BLE packets
(Bluefruit Connect export or `scripts/ble_log.py`), removes duplicates after
reconnects, reports lost samples and the measured sample rate, and plots x,
y, z and magnitude (g). With a timestamped export it adds a wall-clock
`time` per sample (straight-line fit of phone arrival time vs the Tag's
`t_ms`; the date defaults to the file's modification date, override with the
third argument). Files over 100 MB are read with data.table.

`stroke_rate.R` is the prototype of the on-device detector (milestone 5),
using only causal filters that port easily to C:

1. gravity = EMA low-pass per axis (τ 2 s); dynamic = raw − gravity
2. vertical = dynamic · ĝ; horizontal = dynamic − vertical
3. surge axis = first principal component of the horizontal part (offline
   for now), sign chosen so the drive is positive
4. band-pass 0.5–2 Hz (two cascaded RBJ biquads)
5. peaks above max(20 mg, 0.5 × running mean |signal|), ≥ 0.6 s apart
6. spm = 60 / interval, plausible 30–110, rolling median of 5 strokes,
   one value per second (held 5 s, then blank)

With a reference file it aligns the Tag estimate to the watch cadence
(shift with the smallest mean absolute difference within ±60 s, pauses
counting as 0 spm; the shift includes clock offset and both devices'
smoothing delays) and reports bias, MAE, correlation and the median ratio
(a ratio near 0.5 or 2 would mean one device counts one side only).
Outputs: `<session>_strokes.png`, `_zoom.png` (20 s), `_spm.csv`,
`_compare.png`.

Reference formats: **FIT** (converted by `scripts/fit_to_csv.py` with
`fitdecode` in `.venv`; also usable alone:
`.venv/bin/python scripts/fit_to_csv.py activity.fit`), **TCX** (`Cadence`
or `RunCadence`), or **CSV** with columns `time` (ISO 8601, UTC) and
`cadence`. Speed, distance, heart rate and position are kept when present.

Our reference is an **Apple Watch with WorkOutDoors** (FIT export, sport
"paddling", 1 record/s with cadence, speed, distance, heart rate, GPS).
**Does the FIT cadence count every stroke?** Paddler's experience: typical
OC1 stroke rate is ~50/min and the WorkOutDoors display (~85) double
counts, i.e. the file's ~42 is closer to the real rate; to be confirmed by
the Tag. The app showed ~85/min while the file says ~42 (median over a 70-min session
without the Tag, `0926.fit`, 2026-11-17; smooth and step-like, never 0;
records stop when the workout pauses). Distance per stroke doesn't settle
it: at 5.9 km/h → 2.4 m (42) or 1.2 m (85); at 8.7 km/h → 3.4 m or 1.7 m.
`read_reference()` uses the file value as-is (`fit_strokes_per_cycle = 1`);
the Tag comparison's median ratio est/ref (≈1 or ≈2) will decide. A manual
count of strokes over 30 s while paddling also settles it.

Note for M5: Paddle Stroke must also report **strokes**/min, so each detected
stroke adds one crank revolution (85 strokes/min shows as 85 rpm). If the
CS300 should match the watch's cycle count instead, add one revolution per
two strokes.

Synthetic check (10 min, varying 55–80 spm, rotated Tag, reference clock
4 s off): 576 strokes detected vs ~575 true; after alignment MAE 0.3 spm.

**First water session (OC1, 2026-11-18, 18:41–19:26, files
`data/oc1_20261118_*`, not committed).** Tag recorded via Bluefruit
Connect for 1 h 43 min (619 932 samples, 3 lost); Apple Watch WorkOutDoors
in *running* mode by mistake (its FIT `cadence` is then strides/min, i.e.
one per stroke). Analysis restricted to the watch's time span, where the Tag
lay flat (z up); surge axis = Tag x.
- Hull surge shows one smooth cycle per stroke, ~1.45 s, well above the
  wave noise; side switches show as short spikes and could split a peak, so
  the minimum gap is now adaptive (≥ 60 % of the median of the last 8
  intervals).
- 1828 strokes in 45 min, median **41.1 strokes/min**; watch 1906 "strides",
  average 42.
- Per minute: Tag 40.7 ± 2.1, watch 42.2 ± 3.7; MAE 2.4 overall and
  **1.2 spm from 18:57 on**. Before that the watch has bursts to 50–65
  (e.g. 18:56) while the hull shows a steady ~40/min: the watch is wrong
  there.
- Per-second alignment is not meaningful at this steady rate (r ≈ 0); use
  per-minute comparisons.
- So in this session the FIT's ~42 counted every stroke, and the real rate
  was ~41/min (relaxed paddling); the app's on-screen ~85 doubles it.
- Battery 3957 → 3895 mV over 1 h 43 min on battery (logger, GNSS on).

First water test (OC1): Tag rigidly fixed to the hull, phone (Bluefruit
Connect, recording) and watch (paddling activity with stroke rate) both
running; ~30 s still at start and end; 10+ min including steady pieces at
different rates. Export the Bluefruit log and the watch activity (TCX or
FIT), then run `stroke_rate.R` with both.
