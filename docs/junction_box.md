# Junction box: solar + extra battery for the Tag (sidequest, paper design)

Status: design only, nothing built or measured. Current draws below are
estimates until measured (see "Measure first").

## Goal

Keep the Tag running on the boat for days to weeks without taking it home to
charge, in tropical sun and salt spray, without modifying the Tag.

## Key decisions

1. **The Tag lives inside the box.** Its magnetic 4-pin USB connector would
   corrode quickly with 5 V on it in salt water, so the connection stays in
   the dry. The box is mounted rigidly to the hull, and the Tag rigidly to
   the box, so the accelerometer still sees hull motion. BLE passes through
   a plastic box; GNSS too, but not well under the panel.
2. **Feed 5 V into the Tag's own USB input** (the magnetic cable) instead of
   wiring into its battery. No opening of the Tag, its charger and battery
   protection stay in charge, and it can still be pulled out and flashed.
   Cost: a double conversion (battery → 5 V boost → Tag charger), about
   75 % efficient.
3. **Firmware first.** The cheapest energy is the energy not used: GNSS off
   and LEDs dark (milestone 6) probably cut consumption by 3–5×, and may
   make the box unnecessary for normal sessions.

## Block diagram

```
  ┌──────────── lid (outside) ────────────┐
  │   ETFE solar panel 6 V, 1–2 W          │
  └───────────────┬───────────────────────┘
                  │ IP68 gland (or sealed under lid)
  ┌───────────────▼────────── IP67 box ───────────────────────────┐
  │                                                              │
  │  solar ──► Li-ion solar charger ──► 18650 pack (1–2 cells)    │
  │            (bq24074: input DPM for     │  NTC on the cells    │
  │             panels, NTC, load sharing) │                      │
  │                                        ▼                      │
  │                                  polyfuse 1 A                 │
  │                                        ▼                      │
  │                               5 V boost (low Iq) ──► magnetic │
  │                                                     cable ──► │
  │                                                    ┌───────┐  │
  │   vent membrane   desiccant                        │  Tag  │  │
  │                                                    └───────┘  │
  └──────────────────────────────────────────────────────────────┘
```

## Energy budget (estimates)

| Load | Now (M4 firmware) | After M6 power work |
|---|---|---|
| GNSS on the 3.3 V rail (`PIN_3V3_EN` HIGH in `initVariant`) | ~25 mA | 0 (rail off or GNSS standby) |
| nRF52840 + BLE link, 15 ms interval, ~3.5 kB/s | ~2–4 mA | ~1–2 mA (longer interval when not logging) |
| LEDs (green blink, blue solid when connected) | ~2–4 mA | ~0 (brief flashes) |
| LIS2DH at 100 Hz | ~0.01 mA | same |
| **Total** | **~30 mA ≈ 0.75 Ah/day** | **~3–5 mA ≈ 0.1 Ah/day** |

The Tag's own 1000 mAh alone then lasts roughly **1.3 days now** and
**8–14 days after M6** of continuous operation.

Solar in Salvador (about 13° S): roughly 5 peak-sun hours a day on average.
A 1 W panel lying flat on the box, with heat, angle, spray and conversion
losses (assume 40 % of nominal), gives about 2 Wh/day ≈ 0.5 Ah/day at
3.7 V. That covers the post-M6 load several times over and roughly breaks
even with today's firmware. A 2 W panel gives margin for cloudy days, but
needs a larger lid.

Battery: one 18650 (≈3 Ah) gives about 4 days of darkness now and about
4 weeks after M6. Two in parallel only make sense if GNSS must stay on.

## Bill of materials (example parts, to be checked before buying)

| Part | Example | Notes |
|---|---|---|
| Enclosure | IP67 polycarbonate/ABS junction box ~120×80×55 mm, **white or light grey** | dark boxes get far too hot in the sun |
| Solar panel | 6 V 1 W ETFE (~110×70 mm), or 2 W if the lid allows | ETFE survives salt and UV better than epoxy panels |
| Charger | bq24074 solar/USB Li-ion charger board (e.g. Adafruit "Universal USB/DC/Solar Lithium Ion/Polymer charger – bq24074") | input voltage regulation stops a weak panel collapsing; thermistor input; Li-ion 4.2 V only |
| Cells | 1–2 × protected 18650 Li-ion + holder, or a soldered pack with tabs | holders rattle loose with vibration; tabbed packs are more reliable |
| Thermistor | 10 k NTC taped to the cells, wired to the charger's TS pin | blocks charging above ~45 °C |
| Boost | 5 V low-quiescent boost, e.g. TPS61023-based (Adafruit MiniBoost 5 V) | runs continuously; quiescent current matters |
| Fuse | 1 A polyfuse after the cells | |
| Cable | spare WisMesh Tag magnetic cable, USB-A end cut off → boost output | red = 5 V, black = GND (check with a meter) |
| Sealing | IP68 cable gland (panel lead), vent membrane (e.g. M12 Gore-type), silica gel pack | the vent stops temperature swings pulling in damp air |
| Mounting | stainless screws + backing plate or 3M VHB on a clean, flat spot; Tag held in a snug 3D-printed or foam-free cradle | no soft foam between Tag and hull: it filters the stroke signal |
| Protection | conformal coating on the charger and boost boards | |

## Risks and how the design handles them

- **Heat.** Li-ion must not charge above about 45 °C. A white box, the panel
  doubling as a sunshade with an air gap, and the NTC charge cutoff.
  LiFePO4 copes with heat better but needs a different charger (3.6 V).
- **Salt water.** Everything electrical stays inside an IP67 box with a
  sealed lid, gland and vent; nothing powered is exposed.
- **Vibration and shocks.** Tabbed cells, glued or strapped boards, and a
  rigid cradle for the Tag.
- **No buttons through the lid.** The Tag can't be pressed while boxed.
  Wake/sleep has to come from motion (M6); the `dfu` serial command needs
  the box opened anyway.
- **Signals.** BLE through plastic is fine. The panel's cells and backing
  will weaken GNSS if it is ever used: put the Tag at the end of the box
  away from the panel.
- **Effect on stroke data.** The box and cradle add mass and possible
  resonances. Record a session with the Tag mounted directly and one with
  the box, and compare in R.

## Measure first (before buying parts)

1. **Current draw.** Put a USB power meter between charger and Tag once its
   battery is full: the reading is roughly the running current. Do it with
   the current logger, then with a test build that holds `PIN_3V3_EN` LOW.
2. ~~Is the accelerometer on the switched 3.3 V rail?~~ **No** (`t_rail`,
   2026-11-17): the GNSS is on it, the LIS2DH is not. M6 can switch the
   rail (and GNSS) off.
3. **Battery voltage over a session.** Done: the logger writes
   `# battery t_ms=… mv=…` once a minute; `read_battery()` in R.
