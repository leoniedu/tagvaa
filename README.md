# OC6 Stroke — WisMesh Tag as a BLE stroke-rate sensor

Custom firmware for the **RAK WisMesh Tag** that turns it into a Bluetooth LE
Cycling Speed & Cadence sensor, so a COOSPO CS300 shows paddle strokes per
minute as "cadence" on an OC6 outrigger canoe.

## Hardware facts (verified)

| Item | Value | Source |
|---|---|---|
| MCU / radio module | RAK4630 (nRF52840 + SX1262) | Meshtastic variant |
| Meshtastic variant | `variants/nrf52840/rak_wismeshtag` | [meshtastic/firmware @ 6d41e27](https://github.com/meshtastic/firmware/tree/6d41e279f1f51bd59f687b9d441c1bf47b1594fc/variants/nrf52840/rak_wismeshtag) |
| Board JSON | `boards/wiscore_rak4631.json` (S140 v6.1.1, app at `0x26000`) | Meshtastic `boards/` |
| Accelerometer | ST LIS2DH (I2C; address/WHO_AM_I checked in milestone 2) | RAK + Meshtastic docs |
| GNSS | AT6558R on UART1 (RX 15, TX 16) | Meshtastic variant |
| Back button | 1× reset, **2× (double press) = DFU/UF2 bootloader** | [RAK quick start](https://docs.rakwireless.com/product-categories/meshtastic/wismesh-tag/quickstart/) |
| Front button | user button, GPIO P0.09 (pull-up) | Meshtastic variant |
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
.venv/bin/pio run          # builds .pio/build/wismesh_tag/firmware.uf2
```

`scripts/make_uf2.py` converts the hex to UF2 (family `0xADA52840`) after
every build, using `uf2conv.py` from the Adafruit core.

## Flashing (UF2 drag and drop)

1. Connect the Tag with the magnetic USB cable.
2. **Double-press the back button.** A USB drive appears containing
   `CURRENT.UF2`, `INDEX.HTM`, `INFO_UF2.TXT`.
3. Copy `.pio/build/wismesh_tag/firmware.uf2` onto that drive. It reboots
   by itself into the new firmware.

The UF2 only writes the application area (from `0x26000`). The bootloader and
SoftDevice are never touched, so stock firmware can always be restored by the
same drag-and-drop.

### One-time checks before the first flash

- Open `INFO_UF2.TXT` and check the SoftDevice line says **S140 6.1.x**.
  This firmware is linked for S140 6.1.1 (app at `0x26000`). If it says
  7.x, **do not flash** — the layout differs.
- Copy `CURRENT.UF2` from the drive to a safe place: it's a full backup of
  the flash as it is now.

## Reverting to stock Meshtastic

1. Download the latest firmware from <https://meshtastic.org/downloads>
   (or the GitHub releases), nRF52840 zip, and pick
   `firmware-rak_wismeshtag-X.X.X.xxxxxxx.uf2`.
2. Double-press the back button, drag the `.uf2` onto the drive.
3. If Meshtastic misbehaves afterwards (corrupt settings from this
   firmware's BLE bond storage, which shares the flash filesystem area),
   do a factory erase as described in
   <https://meshtastic.org/docs/getting-started/flashing-firmware/nrf52/nrf52-erase/>
   (check `INFO_UF2.TXT` for a `Factory-Erase:` line first; use the erase
   file matching your SoftDevice), then flash Meshtastic again.
   This resets Meshtastic settings, keys and node DB.

## Milestones

1. **Hello world** — USB serial + LED blink. ← current
2. I2C scan, LIS2DH WHO_AM_I, raw x/y/z at 10 Hz.
3. BLE CSC sensor with fixed 60 rpm (go/no-go with CS300).
4. 100 Hz accelerometer logging over BLE UART + R analysis script.
5. On-device stroke detector.
6. Power management.

### Milestone 1 — test

After flashing:

```sh
.venv/bin/pio device list          # find the port, e.g. /dev/cu.usbmodem1101
.venv/bin/pio device monitor       # 115200 baud; Ctrl-C to quit
```

Expected: `OC6 Stroke: hello from the WisMesh Tag`, then `tick N  uptime …`
once per second, while the green and blue LEDs alternate every second.

To go back to the bootloader later: double-press the back button again.
