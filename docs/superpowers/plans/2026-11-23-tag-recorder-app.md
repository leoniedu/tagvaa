# Tag Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each Tag a stable friendly name (`tagvaa honu_A`) and build an iPhone app that records one Tag's raw stream for a whole session without losing data.

**Architecture:** Firmware gets a small plain-C++ library that turns the factory Bluetooth address into a name, used by every BLE firmware. The app is a SwiftUI shell around a Foundation-only Swift package (`RecorderCore`: file writing, stream statistics, the recording state machine behind a `TagLink` protocol), so all logic is tested with `swift test` on the Mac without a Tag or a simulator. CoreBluetooth and CoreLocation live only in the app target.

**Tech Stack:** C++17 (Adafruit nRF52 core, PlatformIO), Swift 5.9+ / SwiftUI / CoreBluetooth / CoreLocation, XcodeGen, iOS 17, R (tidyverse) for the reader change.

**Spec:** `docs/superpowers/specs/2026-11-23-tag-recorder-app-design.md`

## Global Constraints

- Advertised names: `tagvaa <word>_<letter>` (cadence firmwares) and `tagvaa log <word>_<letter>` (logger); word from 6 address bits (64 words), letter A–P from 4 other bits.
- Words: plain ASCII, lowercase, at most 6 letters; the list below is fixed once shipped (order matters).
- Data lands on disk as it arrives; at most the last ~2 s may be lost on power loss. No export step.
- Recording file layout readable by `unpack_bluefruit()` unchanged: header `Timestamp,Mode,Data`, data rows `Mode = RX`, `Timestamp` = phone time of day `HH:mm:ss.SSS`.
- Extra rows use `Mode = INFO` and `Mode = GPS`.
- Manual start; Stop needs press-and-hold; no login.
- iOS 17, iPhone only, bundle ID `com.eleon.tagvaa.recorder`, team `994QVUGPX7`, TestFlight.
- App in `ios/` of the tagvaa repo.
- UI wording in Portuguese (club use; planner's call, see handoff).

## Fixed data (decided here, used by several tasks)

**Word list, index 0–63:**

```
honu nalu mano naia hoku makani moana kai
kohola hee limu ahi aku opah ono mahina
ua ao lani pali iwa manu akule opelu
uhu kala manini weke papio ulua moi mamo
ula kona hau puhi lupe hoe waa ama
iako kia ihu ale opihi wana hokuao malino
ehu lele holo pae au nenue humu kumu
palani maiko nohu hapuu ulaula makau ina piko
```

**Bits:** with the address as delivered by `Bluefruit.getAddr(mac)` (`mac[0]` least significant): word index = `mac[0] & 0x3F`; letter index = `(mac[0] >> 6) | ((mac[1] & 0x03) << 2)`, letter = `'A' + index`.

**Tag identity line**, sent by streaming firmwares in the header each subscriber gets:
`# id name=tagvaa honu_A addr=C5:3A:…:F1` (address most significant byte first).

**Recording rows** (all `Data` fields CSV-quoted, inner quotes doubled):

| Mode | Data |
|---|---|
| `RX` | the BLE packet text exactly as received |
| `INFO` | `start date=2026-11-25 tz=America/Bahia app=1.0 tag=tagvaa honu_A peripheral=<CoreBluetooth UUID>` |
| `INFO` | `link-lost`, `link-restored`, `resumed` (after the app was relaunched), `stop` |
| `GPS` | `lat=-12.97312 lon=-38.51234 speed_ms=2.91 course=181.0 hacc_m=4.0 utc=2026-11-25T09:12:04.120Z` (missing values as `NA`) |

**File name:** advertised name with spaces → `-`, then `_` and local start time: `tagvaa-honu_A_2026-11-25T06-12-04.csv`.

## Review Focus

1. Phone locked, passcode or Face ID prompt, or app switched mid-session → recording continues (on-device check, Task 5).
2. Tag out of range for minutes, then back → one file, `link-lost`/`link-restored` rows, lost samples counted from the `seq` gap (Task 4 test).
3. iOS kills the app in the background → relaunch continues the same file with a `resumed` row and no second header (Task 4 test, Task 5 wiring).
4. Tag reboots mid-session (`seq` restarts near 0) → not counted as lost samples (Task 3 test).
5. File cannot be written (no space, bad directory) → status shows an error instead of looking like it records (Task 4 test).

---

### Task 1: Friendly Tag names in all BLE firmwares

**Files:**
- Create: `lib/tag_name/tag_name.h`, `lib/tag_name/tag_name.cpp`
- Test: `test/host/tag_name_test.cpp`
- Modify: `src/m3_csc/main.cpp`, `src/m4_logger/main.cpp`, `src/m5_stroke/main.cpp`, `src/m5_acf/main.cpp` (the `Bluefruit.setName` calls and, for m4/m5, the subscriber header)
- Modify: `scripts/csc_check.py`, `scripts/ble_log.py` (match by name prefix)
- Modify: `README.md` (BLE names paragraph, quick start pairing step), `site/index.html` ("Send it as cadence" and "Pair" texts), `docs/devlog.md` (note the rename date in the M3 entry)

**Interfaces:**
- Produces (C++, no Arduino includes):
  - `const char* tag_word(uint8_t index);` — index 0–63, the fixed list
  - `void tag_suffix(const uint8_t mac[6], char* out, size_t n);` — writes `honu_A`
  - `void tag_ble_name(const char* prefix, const uint8_t mac[6], char* out, size_t n);` — writes `tagvaa honu_A` for prefix `tagvaa`
  - `void tag_addr_string(const uint8_t mac[6], char* out, size_t n);` — writes `C5:3A:…:F1`, MSB first

- [ ] **Step 1: Write the failing host test** `test/host/tag_name_test.cpp` (plain `assert`, prints `all tag_name tests passed`):
  - `tag_suffix({0,0,0,0,0,0})` == `"honu_A"`
  - `tag_suffix({0x3F,0,…})` == `"piko_A"`
  - `tag_suffix({0xC0,0,…})` == `"honu_D"`
  - `tag_suffix({0x41,0,…})` == `"nalu_B"`
  - `tag_suffix({0xC5,0x03,…})` == `"makani_P"`
  - all 64 words: non-empty, ≤ 6 chars, only `a`–`z`, pairwise distinct
  - for every word, `strlen(tag_ble_name("tagvaa", …))` ≤ 15 (fits the m3 advert next to flags, TX power, appearance and the CSC UUID) and the `tagvaa log` name ≤ 29 (scan response)
  - `tag_addr_string({0xF1,0xE2,0xD3,0xC4,0xB5,0xC5})` == `"C5:B5:C4:D3:E2:F1"`
- [ ] **Step 2: Run it, expect a compile failure** (no `tag_name.h`):
  `c++ -std=c++17 -I lib/tag_name lib/tag_name/tag_name.cpp test/host/tag_name_test.cpp -o .pio/tag_name_test`
- [ ] **Step 3: Implement `lib/tag_name/tag_name.{h,cpp}`** with the word list and bit rules from "Fixed data".
- [ ] **Step 4: Run the test**: same command, then `.pio/tag_name_test` → `all tag_name tests passed`.
- [ ] **Step 5: Use it in the four BLE firmwares.** After `Bluefruit.begin(…)`, read `Bluefruit.getAddr(mac)`, build the name with prefix `tagvaa` (m3, m5_stroke, m5_acf) or `tagvaa log` (m4), pass it to `Bluefruit.setName`, and print `# name <name> addr <addr>` on USB serial at boot. Leave `setModel` strings as they are. In m4, m5_stroke and m5_acf add the `# id name=… addr=…` line to the header sent to each new subscriber, directly after the existing first header line.
- [ ] **Step 6: Scripts.** `csc_check.py` accepts names starting with `tagvaa ` but not `tagvaa log`; `ble_log.py` accepts names starting with `tagvaa log` (keep the UART-service fallback).
- [ ] **Step 7: Build everything**: `.venv/bin/pio run` → 7 environments `SUCCESS`; `strings firmware/m5_acf.uf2 | grep -c "# id name="` ≥ 1.
- [ ] **Step 8: Docs.** README BLE names paragraph: names are `tagvaa <word>_<letter>` / `tagvaa log <word>_<letter>`, derived from the address, stable across reflashing; renamed 2026-11-2x, pair again. Quick start and site: "pick the `tagvaa …` sensor (e.g. `tagvaa honu_A`)".
- [ ] **Step 9: Commit**: `git commit -m "feat: friendly Tag names from the Bluetooth address"` (with the repo's attribution trailer).

---

### Task 2: `RecorderCore` package and the recording file

**Files:**
- Create: `ios/RecorderCore/Package.swift` (library `RecorderCore`, test target `RecorderCoreTests`, platforms iOS 17 / macOS 14, no dependencies)
- Create: `ios/RecorderCore/Sources/RecorderCore/RecordingFile.swift`, `Rows.swift`
- Test: `ios/RecorderCore/Tests/RecorderCoreTests/RecordingFileTests.swift`

**Interfaces:**
- Produces:
  - `public struct GPSFix { lat, lon: Double; speedMS, course, hAccM: Double?; utc: Date }`
  - `enum Rows { static func rx(_ text: String, at: Date, tz: TimeZone) -> String; static func info(_ text: String, at: Date, tz: TimeZone) -> String; static func gps(_ fix: GPSFix, at: Date, tz: TimeZone) -> String }` — each returns one CSV line ending in `\n`
  - `public final class RecordingFile { static func fileName(tagName: String, start: Date, tz: TimeZone) -> String; init(creating url: URL) throws` (writes the header), `init(appendingTo url: URL) throws` (no header), `func write(_ line: String) throws` (to the OS immediately), `func syncIfDue(now: Date)` (fsync when ≥ 2 s since the last sync), `func close() throws }`

- [ ] **Step 1: Write failing tests** in `RecordingFileTests`:
  - `testFileNameReplacesSpaces`: `fileName(tagName: "tagvaa honu_A", start: 2026-11-25 06:12:04 local, tz: America/Bahia)` == `"tagvaa-honu_A_2026-11-25T06-12-04.csv"`
  - `testHeaderThenRows`: create, write `Rows.rx("12,345,1,2,3\n13,", …)` and `Rows.info("link-lost", …)`; reading the file *before* `close()` gives `Timestamp,Mode,Data` then two rows; the RX Data round-trips through a CSV parser (embedded newline and comma preserved, quotes doubled)
  - `testTimestampFormat`: a row at 06:12:04.120 local starts with `06:12:04.120,`
  - `testGPSRow`: fields in the order of "Fixed data", missing `speedMS` written as `NA`
  - `testAppendingDoesNotRepeatHeader`: create, close, reopen with `appendingTo`, write; exactly one header line
  - `testCreateInMissingDirectoryThrows`
- [ ] **Step 2: Run** `cd ios/RecorderCore && swift test` → fails to compile.
- [ ] **Step 3: Implement** `Rows` and `RecordingFile` with `FileHandle` (`seekToEnd` for appending; `synchronize()` in `syncIfDue`).
- [ ] **Step 4: Run** `swift test` → `Executed 6 tests, with 0 failures`.
- [ ] **Step 5: Commit**: `feat(recorder): recording file and row formats`.

---

### Task 3: Stream statistics

**Files:**
- Create: `ios/RecorderCore/Sources/RecorderCore/StreamStats.swift`
- Test: `ios/RecorderCore/Tests/RecorderCoreTests/StreamStatsTests.swift`

**Interfaces:**
- Produces: `public struct StreamStats { var samples: Int; var lostSamples: Int; var batteryMV: Int?; var tagIdLine: String?; mutating func ingest(_ packet: String) }`. A data line is `seq,t_ms,x,y,z` (all integers); `# battery t_ms=… mv=N` sets `batteryMV`; `# id …` sets `tagIdLine`.

- [ ] **Step 1: Write failing tests**:
  - `testCountsSamplesAcrossSplitPackets`: packets `"10,1,0,0,1000\n11,1"`, `"1,0,0,1000\n12,21,0,0,1000\n"` → `samples == 3`, `lostSamples == 0`
  - `testGapCountsLost`: seq 10, 11, 15 → `lostSamples == 3`
  - `testRebootIsNotLoss`: seq 5000, 5001, then 0, 1 → `lostSamples == 0`, `samples == 4`
  - `testBatteryAndId`: `"# battery t_ms=1000 mv=3957\n"` → 3957; `"# id name=tagvaa honu_A addr=C5:B5:C4:D3:E2:F1\n"` → stored
  - `testGarbageLineIgnored`: a glued fragment like `"12,34,5,6"` (4 fields) changes nothing
- [ ] **Step 2: Run** `swift test` → the new tests fail to compile.
- [ ] **Step 3: Implement** `ingest`: keep the trailing partial line between calls; only count complete lines. A `seq` lower than the last one means the Tag restarted: reset the reference without counting loss.
- [ ] **Step 4: Run** `swift test` → all pass.
- [ ] **Step 5: Commit**: `feat(recorder): stream statistics from the Tag lines`.

---

### Task 4: Recording state machine

**Files:**
- Create: `ios/RecorderCore/Sources/RecorderCore/TagLink.swift`, `Recorder.swift`
- Test: `ios/RecorderCore/Tests/RecorderCoreTests/RecorderTests.swift` (with a `FakeLink` and a settable clock)

**Interfaces:**
- Consumes: `RecordingFile`, `Rows`, `GPSFix` (Task 2), `StreamStats` (Task 3).
- Produces:
  - `public protocol TagLink: AnyObject { var delegate: TagLinkDelegate? { get set }; func connect(peripheralID: UUID); func disconnect() }` — `connect` keeps trying until it succeeds (CoreBluetooth pending connection semantics)
  - `public protocol TagLinkDelegate: AnyObject { func linkConnected(); func linkReceived(_ data: Data); func linkDropped() }`
  - `public struct TagInfo: Codable { let name: String; let peripheralID: UUID }`
  - `public enum RecorderState: Equatable { case idle, connecting, recording, reconnecting, failed(String) }`
  - `public final class Recorder: TagLinkDelegate { init(link: TagLink, directory: URL, now: @escaping () -> Date, tz: TimeZone, appVersion: String); var state: RecorderState; var stats: StreamStats; var fileURL: URL?; var startedAt: Date?; var onChange: (() -> Void)?; func start(tag: TagInfo) ; func stop(); func add(_ fix: GPSFix); func resume(tag: TagInfo, fileURL: URL, startedAt: Date); var activeSession: (tag: TagInfo, fileURL: URL, startedAt: Date)? }`

- [ ] **Step 1: Write failing tests**:
  - `testStartCreatesFileWithStartInfo`: `start` → state `.connecting`, file has header + `INFO start date=… tz=… app=… tag=tagvaa honu_A peripheral=<uuid>`, `link.connect` called with the UUID
  - `testReceivedPacketsAreWrittenAndCounted`: `linkConnected()` → `.recording`; two `linkReceived` → two `RX` rows on disk before `stop()`; `stats.samples` updated
  - `testDropWritesLostAndReconnects`: `linkDropped()` → `.reconnecting`, `INFO link-lost` row, `connect` called again; `linkConnected()` → `INFO link-restored`, `.recording`; same file throughout
  - `testGapAfterReconnectCountsLost` (Review Focus 2): seq 1–3, drop, reconnect, seq 50 → `lostSamples == 46`
  - `testStopClosesAndDisconnects`: `INFO stop` row, `link.disconnect()` called, state `.idle`, `activeSession == nil`
  - `testGPSRowsOnlyWhileRecording`: `add(fix)` before `start` writes nothing; during recording writes one `GPS` row
  - `testResumeAppendsWithoutHeader` (Review Focus 3): start, write, simulate kill (drop the object), new `Recorder` → `resume(...)` → one header, an `INFO resumed` row, `connect` called
  - `testUnwritableDirectoryFails` (Review Focus 5): directory is a file path → `start` sets `.failed(message)` and does not call `connect`
- [ ] **Step 2: Run** `swift test` → fail.
- [ ] **Step 3: Implement** `Recorder`. Every received packet is written at once and followed by `syncIfDue(now: now())`. `activeSession` is what the app persists for relaunch; `resume` reopens with `RecordingFile(appendingTo:)`. Write failures after start set `.failed` and stop calling the link.
- [ ] **Step 4: Run** `swift test` → all pass.
- [ ] **Step 5: Commit**: `feat(recorder): recording state machine with reconnect and resume`.

---

### Task 5: iPhone app

**Files:**
- Create: `ios/project.yml` (app target `TagRecorder`, product name `tagvaa`, depends on local package `RecorderCore`, team `994QVUGPX7`, automatic signing)
- Create: `ios/TagRecorder/Info.plist` — `NSBluetoothAlwaysUsageDescription`, `NSLocationWhenInUseUsageDescription`, `UIBackgroundModes` = `bluetooth-central`, `location`
- Create: `ios/TagRecorder/TagRecorderApp.swift`, `BLETagLink.swift`, `PhoneGPS.swift`, `SessionStore.swift`, `Views/RecordView.swift`, `Views/HoldToStopButton.swift`, `Views/RecordingsView.swift`
- Modify: `.gitignore` (`ios/*.xcodeproj`, `ios/RecorderCore/.build`)

**Interfaces:**
- Consumes: `TagLink`, `TagLinkDelegate`, `Recorder`, `TagInfo`, `GPSFix`, `RecorderState`, `StreamStats` (Task 4).
- Produces: `final class BLETagLink: NSObject, TagLink` with `func scan(_ found: @escaping (TagInfo, Int /*RSSI*/) -> Void)`, `func stopScan()`.

- [ ] **Step 1: BLETagLink.** `CBCentralManager` with restore identifier `tagvaa.recorder`. Scan with no service filter, keep peripherals whose local name starts with `tagvaa`. On connect: discover the Nordic UART service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, subscribe to TX `6E400003-B5A3-F393-E0A9-E50E24DCCA9E`, then call `linkConnected()`; notifications → `linkReceived`; disconnect → `linkDropped()`. `connect(peripheralID:)` uses `retrievePeripherals(withIdentifiers:)` and `connect` (no timeout).
- [ ] **Step 2: PhoneGPS.** `CLLocationManager`, when-in-use authorization requested on first Record, `allowsBackgroundLocationUpdates = true`, `showsBackgroundLocationIndicator = true`, best accuracy; each location → `GPSFix` → `recorder.add`. Runs only while recording.
- [ ] **Step 3: SessionStore.** Persists `recorder.activeSession` (tag, file URL, start) in `UserDefaults` on start, clears it on stop; at launch (including Bluetooth state restoration) a stored session calls `recorder.resume`. Also remembers the last `TagInfo` used, for preselection. Recordings live in the app's Documents folder.
- [ ] **Step 4: Views** (Portuguese). `RecordView`: scan list with the last Tag preselected; big **Gravar** button; while recording one status block: Tag name, link state (`gravando`, `reconectando…`, `erro: …`), elapsed `mm:ss`, `amostras perdidas: N`, `bateria do Tag: 3.96 V`; `HoldToStopButton` stops after a 2 s press with a progress ring; a tap shows "segure para parar". `RecordingsView`: files newest first with size and duration, `ShareLink` per file; files can be deleted by swipe.
- [ ] **Step 5: Build**: `cd ios && xcodegen generate && xcodebuild -project TagRecorder.xcodeproj -scheme TagRecorder -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`; `cd RecorderCore && swift test` still green.
- [ ] **Step 6: On-device check** (owner, with a Tag on `m5_acf` from Task 1), each item ticked in the commit message or a note:
  1. Record 5 min; lock the phone, wait, unlock with passcode, switch apps → no gap in `seq` beyond normal BLE loss (Review Focus 1).
  2. Walk out of range ~2 min and back → one file, `link-lost` / `link-restored` rows, recording continues.
  3. While recording in the background, kill the app from the switcher, relaunch → same file continues with `resumed`.
  4. Tap Stop → keeps recording; hold 2 s → stops.
  5. Share the file by AirDrop; `Rscript analysis/read_accel.R <file>` plots it.
- [ ] **Step 7: Commit**: `feat(recorder): iPhone app for recording a Tag`.

---

### Task 6: R reader takes the date from the recording

**Files:**
- Modify: `analysis/read_accel.R` (`read_stream_lines`, `read_accel`)
- Create: `test/r/fixtures/recorder_sample.csv` (header, `INFO start date=2026-11-25 tz=America/Bahia …`, a few `RX` rows with a split line, one `GPS` row), `test/r/test_read_accel.R`
- Modify: `docs/analysis.md` (recording with the app replaces Bluefruit as the first choice; Bluefruit stays as fallback)

**Interfaces:**
- Consumes: row formats from "Fixed data".
- Produces: `read_stream_lines(path)` returns `list(lines, clock, info)` where `info` is a tibble (`phone_s`, `text`) of `INFO` rows (empty for Bluefruit files); `read_accel(path, date = NULL, tz = NULL)` uses the `start` row's `date` and `tz` when the arguments are `NULL`, else the old defaults (file date, `Sys.timezone()`).

- [ ] **Step 1: Write the failing test** `test/r/test_read_accel.R` (sources `analysis/read_accel.R`, uses `stopifnot`, prints `read_accel tests passed`): on the fixture, `read_accel()` returns the expected number of samples, `as.Date(min(time), tz = "America/Bahia") == as.Date("2026-11-25")` although the file's modification date differs (set it with `Sys.setFileTime`), and the `GPS` row does not become a data line.
- [ ] **Step 2: Run** `Rscript test/r/test_read_accel.R` → fails on the date.
- [ ] **Step 3: Implement** the `INFO` parsing (`Mode == "INFO"` rows, `date=` and `tz=` from the `start` row).
- [ ] **Step 4: Run** the test → `read_accel tests passed`; `Rscript analysis/read_accel.R data/oc1_20261118_tag.csv` still reads the old Bluefruit file.
- [ ] **Step 5: Docs and commit**: `feat: read_accel takes date and time zone from recorder files`.
