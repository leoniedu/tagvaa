# tagvaa — WisMesh Tag as a BLE stroke-rate sensor

Custom firmware for the **RAK WisMesh Tag** that turns it into a Bluetooth LE
Cycling Speed & Cadence sensor, so a COOSPO CS300 shows paddle strokes per
minute as "cadence" on an outrigger canoe (tested in an OC6; OC1 not yet tested).

It **replaces Meshtastic**: while it runs, the Tag is no longer a tracker or a
mesh node. The GPS is powered off, the LoRa radio is never used, and only the
accelerometer and Bluetooth remain. Flash stock Meshtastic to get the tracker
back (see [Reverting](docs/flashing.md#reverting-to-stock-meshtastic)).

**Mounting.** The Tag is rated IP66: protected against rain, spray and strong
water jets, but not rated for being underwater (that would be IP67). Preferably
put it inside a sealed plastic junction box (IP67 or better; plastic so
Bluetooth gets through). Fix the box rigidly to the boat and the Tag rigidly
inside it, so the Tag still feels the boat's motion (see
[docs/junction_box.md](docs/junction_box.md)). Otherwise, mount it where water
runs off rather than pools, not where bilge water collects.

BLE names: **tagvaa** (cadence sensor, M3/M5) and **tagvaa log** (raw data
logger, M4). Renamed from "Paddle Stroke" / "Paddle Logger" on 2026-11-23 and
from "OC6 …" on 2026-11-17; a phone or CS300 that paired earlier may still
show an old name until it is forgotten.

> **Warning — use at your own risk.** This is experimental firmware for a
> device it was not made for. Flashing it can leave your Tag unusable
> ("bricked"), wipe your Meshtastic settings and keys, or drain the battery.
> Back up first (see [flashing](docs/flashing.md)) and read
> [Reverting to stock Meshtastic](docs/flashing.md#reverting-to-stock-meshtastic).
> It comes with no warranty; see the [license](LICENSE).

Project page: <https://leoniedu.github.io/tagvaa/>

## Ready-made alternatives

If you want something finished, waterproof and supported:
[NK SpeedCoach OC 2](https://westcoastpaddlesports.com/products/speedcoach-oc) (outrigger stroke-rate and GPS speed display, about
US$470) or the [Vaaka Cadence](https://threeoceans.co/products/vaaka-cadence-sensor) sensor (on the paddle, Bluetooth and
ANT+, about US$225). This project is the cheap, experimental route for people
who already own a Bluetooth head unit.

## Which firmware

| File | Use it for |
|---|---|
| `m5_acf.uf2` | **Stroke rate on the head unit.** Autocorrelation tracker; steadiest. Being tested on the water. |
| `m5_stroke.uf2` | Same job with the older peak-counting detector (fallback). |
| `m4_logger.uf2` | Recording the raw 100 Hz accelerometer stream to a phone or Mac. |

The other environments (`m1_hello`, `m2_accel`, `m3_csc`, `t_rail`) are
bring-up tests; see the [development log](docs/devlog.md).

## Where to buy

The WisMesh Tag is sold by [RAK's own store](https://store.rakwireless.com/products/wismesh-tag-meshtastic-gps-lora-tracker-ip66) (about US$39) and by
[RAK's official store on AliExpress](https://www.aliexpress.com/item/1005009754254701.html). Make sure you get the magnetic USB
cable: it is the only way to charge and flash the Tag. The LoRa band doesn't
matter for this firmware, but pick your region's band if you might go back to
Meshtastic.

## Quick start

1. Build (PlatformIO in a local virtual environment):

   ```sh
   python3 -m venv .venv
   .venv/bin/pip install platformio
   .venv/bin/pio run -e m5_acf      # writes firmware/m5_acf.uf2
   ```

2. Enter the UF2 bootloader: from stock Meshtastic run
   `.venv/bin/meshtastic --port /dev/cu.usbmodem* --enter-dfu`; from this
   firmware type `dfu` in `.venv/bin/pio device monitor` or hold the front
   button 5 s. A drive named `RAK4631` appears.
3. Open `INFO_UF2.TXT`: the SoftDevice must be **S140 6.1.x** (if 7.x, stop).
   Copy `CURRENT.UF2` somewhere safe as a full backup.
4. Copy `firmware/m5_acf.uf2` onto the drive; the Tag reboots by itself.
5. On the head unit, add a cadence sensor and pick **tagvaa**.

Details and edge cases: [docs/flashing.md](docs/flashing.md).

## Documentation

- [docs/flashing.md](docs/flashing.md): toolchain, bootloader, backups, stock firmware, reverting to Meshtastic
- [docs/hardware.md](docs/hardware.md): verified hardware facts, pin map, 3.3 V rail test
- [docs/analysis.md](docs/analysis.md): the 100 Hz logger, recording a session, R analysis, water session results
- [docs/devlog.md](docs/devlog.md): milestone notes, bug post-mortems, tuning and bench results
- [docs/junction_box.md](docs/junction_box.md): sidequest, solar + battery box (paper design)

## License

GPL-3.0 (see [LICENSE](LICENSE)). The board and pin definitions are derived
from [Meshtastic](https://github.com/meshtastic/firmware), which is GPL-3.0.
This program is distributed WITHOUT ANY WARRANTY, without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
