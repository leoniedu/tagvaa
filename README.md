# Paddle Stroke — WisMesh Tag as a BLE stroke-rate sensor

Custom firmware for the **RAK WisMesh Tag** that turns it into a Bluetooth LE
Cycling Speed & Cadence sensor, so a COOSPO CS300 shows paddle strokes per
minute as "cadence" on an outrigger canoe (first tests in an OC1, target OC6).

BLE names: **Paddle Stroke** (cadence sensor, M3/M5) and **Paddle Logger**
(raw data logger, M4). Renamed from "OC6 …" on 2026-11-17; a phone or CS300
that paired earlier may still show the old name until it is forgotten.

## Hardware facts (verified)

| Item | Value | Source |
|---|---|---|
| MCU / radio module | RAK4630 (nRF52840 + SX1262) | Meshtastic variant |
| Meshtastic variant | `variants/nrf52840/rak_wismeshtag` | [meshtastic/firmware @ 6d41e27](https://github.com/meshtastic/firmware/tree/6d41e279f1f51bd59f687b9d441c1bf47b1594fc/variants/nrf52840/rak_wismeshtag) |
| Board JSON | `boards/wiscore_rak4631.json` (S140 v6.1.1, app at `0x26000`) | Meshtastic `boards/` |
| Accelerometer | ST LIS2DH at I2C **0x19**, WHO_AM_I **0x33** (only device on the bus) | RAK + Meshtastic docs; verified M2 |
| GNSS | AT6558R on UART1 (RX 15, TX 16) | Meshtastic variant |
| Back button | per RAK: 1× reset, 2× = DFU/UF2 bootloader. **Not visible on our unit** (only one button found), so we enter the bootloader by software instead | [RAK quick start](https://docs.rakwireless.com/product-categories/meshtastic/wismesh-tag/quickstart/) |
| Front button | the one visible button; GPIO P0.09, active low (pull-up) | Meshtastic variant; verified M1 |
| LEDs | green P1.03 (pin 35), blue P1.04 (pin 36), red = charger only | Meshtastic variant + RAK docs |

### Pins used

| Function | Arduino pin | nRF GPIO |
|---|---|---|
| Green LED | 35 | P1.03 |
| Blue LED | 36 | P1.04 |
| I2C SDA | 25 | P0.25 |
| I2C SCL | 24 | P0.24 |
| 3.3 V peripheral rail enable (set HIGH at boot) | 34 | P1.02 |
| User button | 9 | P0.09 |
| Battery sense (0.6 × VBAT) | 5 (A0) | P0.05 |

Arduino pin numbers equal nRF GPIO numbers (P1.x = 32 + x); see
`variants/wismesh_tag/variant.cpp`.

## Toolchain (macOS, Apple Silicon)

Same versions Meshtastic pins in `variants/nrf52840/nrf52.ini`:

- `platformio/nordicnrf52@11.0.0`
- `framework-arduinoadafruitnrf52` from Meshtastic's fork, commit `0fd295f`
- `toolchain-gccarmnoneeabi@1.120301.0`

Setup (nothing installed system-wide; PlatformIO lives in `.venv/`, its
packages in `~/.platformio/`):

```sh
python3 -m venv .venv
.venv/bin/pip install platformio
.venv/bin/pio run               # builds all milestones -> firmware/<env>.uf2
.venv/bin/pio run -e m3_csc     # build one milestone
```

There is one PlatformIO environment per milestone (`src/m1_hello`,
`src/m2_accel`, `src/m3_csc`, `src/m4_logger`); `lib/lis2dh` is the shared
accelerometer driver. `scripts/make_uf2.py` converts each hex to
`firmware/<env>.uf2` (family `0xADA52840`) using `uf2conv.py` from the
Adafruit core. All images start at `0x26000` and end below `0x44000`.

## Flashing (UF2 drag and drop)

### Getting into the UF2 bootloader (no button needed)

Our unit shows only one button, so we use software entry:

| Tag is running | How |
|---|---|
| Stock Meshtastic | `.venv/bin/meshtastic --port /dev/cu.usbmodem* --enter-dfu` (Meshtastic calls `enterUf2Dfu()`; documented in [Meshtastic: entering bootloader mode](https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/entering-bootloader-mode/)) |
| Any firmware here | type `dfu` + Enter in `pio device monitor`, or hold the front button 5 s (`lib/dfu_escape`) |
| Neither works | RAK documents a double press of the reset ("back") button |

The Meshtastic CLI is installed in `.venv` (`pip install meshtastic`).

A USB drive named **`RAK4631`** appears containing `CURRENT.UF2`,
`INDEX.HTM`, `INFO_UF2.TXT`. Our unit's `INFO_UF2.TXT` (verified 2026-11-17):

```
UF2 Bootloader 0.4.3
Model: WisBlock RAK4631 Board
Board-ID: WisBlock-RAK4631-Board
Date: May 20 2023
SoftDevice: S140 6.1.1
```

No `Factory-Erase:` line, so a factory erase needs
`Meshtastic_nRF52_factory_erase_v3_S140_6.1.0.uf2`, not
`meshtastic_factory_erase.uf2`. macOS `cp` usually ends with
`fcopyfile failed: Input/output error`: harmless, the bootloader
rebooted as soon as it had the whole file.
Copy `firmware/<milestone>.uf2` onto it; the Tag reboots into the new
firmware by itself.

Shortcut when one of our firmwares is running: `scripts/flash.sh firmware/m3_csc.uf2`
(sends `dfu`, waits for the drive, checks the SoftDevice, copies the file).

The UF2 only writes the application area (from `0x26000`). The bootloader and
SoftDevice are never touched, so stock firmware can always be restored by the
same drag-and-drop.

### Meshtastic config backup

Before the first flash, the stock config was exported with
`meshtastic --export-config` to `firmware/backup/meshtastic-config-2.7.26.yaml`
(not committed: contains channel keys). A full flash image from the
bootloader is in `firmware/backup/CURRENT-before-m1.UF2`
(sha256 `3b14385a…`). Restore after reverting with
`meshtastic --configure firmware/backup/meshtastic-config-2.7.26.yaml`.

### One-time checks before the first flash

- Open `INFO_UF2.TXT` and check the SoftDevice line says **S140 6.1.x**.
  This firmware is linked for S140 6.1.1 (app at `0x26000`). If it says
  7.x, **do not flash** — the layout differs. (Expected: Meshtastic's
  WisMesh Tag bootloader release is `wismesh_tag_bootloader-2.6.1_s140_6.1.1`,
  and the stock Tag UF2 also starts at `0x26000`.)
- Copy `CURRENT.UF2` from the drive to a safe place: it's a full backup of
  the flash as it is now.

## Stock firmware (downloaded to `firmware/stock/`, not committed)

| File | Source | SHA-256 |
|---|---|---|
| `firmware-rak_wismeshtag-2.7.26.54e0d8d.uf2` | meshtastic/firmware release `v2.7.26.54e0d8d` (latest stable), `firmware-nrf52840-*.zip` | `fc036c376133b4217db30c8178f8f2d2357276b68d63f304295f2beefef96cf3` |
| `meshtastic_factory_erase.uf2` | meshtastic/nRF52_Bootloader release `2.6.1` (needs `Factory-Erase:` in `INFO_UF2.TXT`) | `6ef3146505c40079ee9e7e692448e40a793dad636f55d1545063299d28908f0d` |
| `Meshtastic_nRF52_factory_erase_v3_S140_6.1.0.uf2` | same firmware zip (for older bootloaders with S140 6.x) | `e082c085d2dbf58feac73c6bf47a9a148909c7613069493a4488d640714a4f34` |
| `wismesh_tag_bootloader-2.6.1_s140_6.1.1.zip` | meshtastic/nRF52_Bootloader `2.6.1` (reference only; not needed) | `16799695b3ec1774da679b81c606b81f7cdaa049e7b4db53c21cf59bb94e56c7` |

Re-download:

```sh
mkdir -p firmware/stock && cd firmware/stock
gh release download v2.7.26.54e0d8d -R meshtastic/firmware -p 'firmware-nrf52840-*.zip'
unzip -j firmware-nrf52840-*.zip 'firmware-rak_wismeshtag-*.uf2' 'Meshtastic_nRF52_factory_erase_v3_S140_6.1.0.uf2'
gh release download 2.6.1 -R meshtastic/nRF52_Bootloader -p meshtastic_factory_erase.uf2
```

## Reverting to stock Meshtastic

1. Use `firmware/stock/firmware-rak_wismeshtag-2.7.26.54e0d8d.uf2`, or the
   latest from <https://meshtastic.org/downloads>
   (`firmware-rak_wismeshtag-X.X.X.xxxxxxx.uf2` in the nRF52840 zip).
2. Enter the bootloader (type `dfu` in the serial monitor), drag the `.uf2` onto the drive.
3. If Meshtastic misbehaves afterwards (corrupt settings from this
   firmware's BLE bond storage, which shares the flash filesystem area),
   do a factory erase as described in
   <https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/nrf52-erase/>
   (check `INFO_UF2.TXT` for a `Factory-Erase:` line first; use the erase
   file matching your SoftDevice), then flash Meshtastic again.
   This resets Meshtastic settings, keys and node DB.

## Milestones

| # | Env / UF2 | What it does | Status |
|---|---|---|---|
| 1 | `m1_hello` | USB serial + LED blink | ✅ verified 2026-11-17 (serial, both LEDs, button, `dfu` escape) |
| 2 | `m2_accel` | I2C scan, LIS2DH WHO_AM_I, x/y/z at 10 Hz | ✅ verified 2026-11-17 (0x19, 0x33, \|a\| ≈ 0.99 g at rest) |
| 3 | `m3_csc` | BLE CSC sensor, fixed 60 rpm (go/no-go) | ✅ **GO** 2026-11-17: CS300 shows 60 rpm |
| 4 | `m4_logger` | 100 Hz accel over BLE UART (FIFO) + R script | ✅ 2026-11-17: Mac and iPhone (Bluefruit Connect), 0 lost, ~100.6 Hz; boat session pending |
| 5 | — | On-device stroke detector | after real data |
| 6 | — | Power management | later |

Serial monitor (any milestone): `.venv/bin/pio device monitor`
(115200 baud, Ctrl-C quits). Back to the bootloader: type `dfu` + Enter in the
monitor, or hold the front button 5 s.

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
  `t_ms` the device uptime (for aligning with other recordings). `#` lines
  are comments, including `# FIFO overrun …`.
- Requests MTU 247, 2M PHY and a 15 ms connection interval.
- Phone recording (verified 2026-11-17, iPhone): **Bluefruit Connect** →
  connect (the phone may show the Tag's old Meshtastic name, e.g.
  `Skei_c129`; if connecting fails, Settings → Bluetooth → Forget This
  Device) → UART → record → export as CSV/text. The export is
  `Timestamp,Mode,Data` with one BLE packet per row; `read_accel()` detects
  it and rejoins lines split across packets. First test: 94.5 s, 0 lost,
  100.61 Hz.
- From the Mac over BLE: `.venv/bin/python scripts/ble_log.py data/session.csv 60`.
  Over USB: `.venv/bin/pio device monitor --raw --quiet | tee data/session.csv`.
  `data/` is not committed.

Analysis:

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
In a 70-min session without the Tag (`0926.fit`, 2026-11-17) its cadence
was smooth and step-like, 30–60 spm (median 42), never 0; when the workout
pauses, records stop rather than dropping to 0. A median near 42 is low for
OC paddling, so whether it counts every stroke is one of the things the
comparison should answer (see the ratio).

Synthetic check (10 min, varying 55–80 spm, rotated Tag, reference clock
4 s off): 576 strokes detected vs ~575 true; after alignment MAE 0.3 spm.

First water test (OC1): Tag rigidly fixed to the hull, phone (Bluefruit
Connect, recording) and watch (paddling activity with stroke rate) both
running; ~30 s still at start and end; 10+ min including steady pieces at
different rates. Export the Bluefruit log and the watch activity (TCX or
FIT), then run `stroke_rate.R` with both.
