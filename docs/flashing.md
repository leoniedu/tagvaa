# Building and flashing

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

## Serial monitor

Serial monitor (any milestone): `.venv/bin/pio device monitor`
(115200 baud, Ctrl-C quits). Back to the bootloader: type `dfu` + Enter in the
monitor, or hold the front button 5 s.
