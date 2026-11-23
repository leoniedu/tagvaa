# Tag recorder app — design (short)

Status: proposed 2026-11-23, awaiting approval.

## Why

A two-boat crossover session (two OC6 crews, side by side, swapping hulls
halfway) will test whether averaged stroke curves from the hull Tag measure the
crew or the boat, and whether they survive open water. That needs the raw
100 Hz stream from **two** Tags for ~75 minutes each.

Bluefruit Connect, used so far, lost data twice over: recording stopped when
the phone asked for a password, and nothing is written until you press
Export. The recorder exists to make losing a session hard.

## Goals

- Record the raw stream of one Tag to the phone for a whole session, with the
  phone locked in a dry bag.
- Never lose what was already received: data is on disk within seconds.
- Tell two Tags apart, on the phone and on the CS300.
- Output that the existing R analysis (`analysis/read_accel.R`) reads unchanged.

## Non-goals

- No analysis or charts in the app; no live stroke rate (the CS300 does that).
- No upload to the R2 store or YachtVAA hand-over yet (project 3 decides
  between direct upload and a shared App Group folder).
- No Android, no App Store release (TestFlight only).
- No new recorder firmware; the Tag keeps running `m5_acf`.

## Anti-goals

- A recording that silently stops, or that only exists after an action by the
  user.
- Needing a login or account to record.

## Constraints

- `m5_acf` already streams raw samples plus `#` lines over the Nordic UART
  service to a second connection while the CS300 holds the first.
- iOS keeps a Bluetooth central running in the background only with the
  `bluetooth-central` background mode.
- The tagvaa repo is GPL-3.0; the app is entirely the owner's code, so its
  licence can be chosen before any public release.

## Approaches

| | |
|---|---|
| **Native iPhone app (SwiftUI + CoreBluetooth) in the tagvaa repo** — chosen | Same stack as YachtVAA (XcodeGen, iOS 17), so its build and TestFlight setup carry over. |
| Web page with Web Bluetooth | Safari on iPhone does not support it. |
| Patch Adafruit's open-source Bluefruit app | Large codebase to fix for exactly the two failures seen; still not ours. |
| Flutter / React Native | Only pays off for Android; one iPhone per boat covers the test. |
| Add the recorder to YachtVAA | Rejected: YachtVAA needs a Treinus login, has testers and cross-checked analysis code; a recorder that changes daily should not ride on it. |

## Decided

**Recording**
- Manual start: pick the Tag, press Record.
- Stop needs a deliberate press-and-hold (or a confirmation); an accidental
  tap must not end a session.
- Recording runs in a background component independent of the screen: lock,
  passcode or Face ID prompts, and switching apps do not affect it
  (`bluetooth-central` background mode).
- Every received packet is appended to the file and flushed within ~2 s.
  There is no export step; sharing sends the file that already exists. A
  crash or a dead phone loses at most the last seconds.
- If the link drops, the app reconnects to the same Tag by itself and keeps
  writing to the same file; the gap is marked in the file.

**Choosing the Tag**
- Scan list of nearby Tags (by the UART service and the `tagvaa` name); the
  last one used is remembered and preselected.

**Screen**
- One status block: Tag name, link state, elapsed time, samples lost (from
  gaps in `seq`), Tag battery (from `# battery` lines).
- A list of recordings with a share button (AirDrop, Files).

**File format**
- One CSV file per recording, named with the Tag ID and start time, e.g.
  `tagvaa-3F2A_2026-11-25T06-12-04.csv`.
- Same layout as the Bluefruit export, so `unpack_bluefruit()` reads it
  unchanged: header `Timestamp,Mode,Data`, one row per BLE packet with
  `Mode = RX`, `Timestamp` as phone time of day with milliseconds.
- Extra rows use other `Mode` values, which the current reader ignores:
  `INFO` (date, time zone, app version, Tag ID; reconnects and gaps) and
  `GPS` (phone position, speed and accuracy, about once a second).

**Phone GPS**
- Logged while recording, with "while using" permission (recording always
  starts with the app open). Gives each hull its own track and a clock
  without watches.

**Firmware change (tagvaa, all BLE firmwares)**
- Advertise as `tagvaa XXXX` and `tagvaa log XXXX`, where `XXXX` is the last
  four hex digits of the Tag's Bluetooth address. The ID is the hull's
  identity in the data. Head units and phones paired with plain `tagvaa`
  must pair again.

**Where**
- App in `ios/` in the tagvaa repo, XcodeGen `project.yml`, iOS 17,
  bundle ID under `com.eleon`, distributed through TestFlight.

## Left to the builder

- Exact screen layout and wording.
- How the `INFO` and `GPS` rows encode their fields.
- Flush mechanism and interval (within the ~2 s bound).
- Small R change so `read_accel()` takes the date from the `INFO` row
  instead of the file's modification date.
- Tests: file writing and reconnection logic should be testable without a
  Tag (simulated packet stream).

## Related

- Project 1 (R dry run of averaged stroke curves on the 2026-11-18 data) gets
  its own short design.
- Order: R dry run and this recorder (in parallel) → two-boat crossover
  session → analysis → decide what the recorder firmware stores.
