# Hardware

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

## 3.3 V rail test (`t_rail.uf2`)

Meshtastic drives `PIN_3V3_EN` (P1.02) HIGH and calls it the GNSS / 3.3 V
peripheral rail. This test reports, with the rail ON, OFF and ON again: I2C
line levels (it skips I2C if they are low, so a bus without pull-up power
can't hang the firmware), the I2C scan and LIS2DH WHO_AM_I, how many NMEA
bytes the GNSS sends on Serial1 (9600 baud) in 3 s, and the battery voltage.
Then it toggles the rail every 30 s (green LED = rail on) so a USB power
meter shows the current difference; the Tag battery should be full so
charging doesn't mask it.

Result (2026-11-17, indoors): rail OFF → GNSS sends 0 bytes, rail ON → it
boots (`$GPTXT … MA=CASIC`, `IC=AT6558R-5N-…`) and streams NMEA at 9600
baud. The LIS2DH (0x19) answers with normal readings with the rail on and
off, and the I2C lines stay high, so the accelerometer and its pull-ups
are on the always-on supply. Milestone 6 can switch GNSS off with
`PIN_3V3_EN` LOW without losing the stroke sensor. Current difference not
yet measured (needs a USB power meter).
