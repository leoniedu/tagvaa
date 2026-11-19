// Milestone 5: on-device stroke detection -> BLE cadence (CSC) for the CS300.
//
// - LIS2DH at 100 Hz (FIFO) -> StrokeDetector (lib/stroke, ported from R)
// - each confirmed stroke = one crank revolution; CSC Measurement notified
//   once a second, so the head unit shows strokes/min (and 0 when stopped)
// - Nordic UART: same raw stream as the logger (seq,t_ms,x_mg,y_mg,z_mg) plus
//   "# stroke n=.. seq=.. t_ms=.." and "# battery" lines, for validation
// - two connections (head unit + phone); GNSS rail off; blue LED off;
//   green blinks briefly on each stroke
#include <Adafruit_TinyUSB.h>
#include <Arduino.h>
#include <Wire.h>
#include <battery.h>
#include <bluefruit.h>
#include <dfu_escape.h>
#include <lis2dh.h>
#include <stroke_detector.h>

constexpr uint16_t APPEARANCE_CADENCE_SENSOR = 0x0483;
constexpr uint8_t CSC_FLAG_CRANK_DATA = 0x02;
constexpr uint16_t CSC_FEATURE_CRANK = 0x0002;
constexpr uint8_t SENSOR_LOCATION_OTHER = 0x00;
constexpr uint8_t MAX_CONNECTIONS = 2;
constexpr uint32_t SAMPLE_PERIOD_MS = 10;
constexpr uint32_t POLL_MS = 50;
constexpr uint32_t CSC_EVERY_MS = 1000;
constexpr uint32_t BATTERY_EVERY_MS = 60000;
constexpr uint32_t LED_BLINK_MS = 30;
constexpr uint32_t HEARTBEAT_MS = 5000; // short blink so you can see it's on

LIS2DH accel;
StrokeDetector detector;

BLEService cscService(UUID16_SVC_CYCLING_SPEED_AND_CADENCE);
BLECharacteristic cscMeasurement(UUID16_CHR_CSC_MEASUREMENT);
BLECharacteristic cscFeature(UUID16_CHR_CSC_FEATURE);
BLECharacteristic sensorLocation(UUID16_CHR_SENSOR_LOCATION);
BLEUart bleuart;
BLEDis deviceInfo;
BLEBas battery;

uint16_t crankRevs = 0;          // cumulative strokes (wraps at 65536)
uint16_t lastCrankEventTime = 0; // time of the last stroke, 1/1024 s (wraps)

// Smoothing. The head unit shows 60 / (time between the last two strokes),
// so it jumps with every stroke. The stroke count stays exact; only the
// reported stroke times are spaced at a smoothed interval: the mean of the
// last SMOOTH_N intervals without their shortest and longest, nudged 5 % per
// stroke toward the real stroke time so it can't drift away (a hard resync
// shows as one bogus value). After a pause it restarts from real time.
// Replayed on the OC1 session: per-stroke 41.9 +- 6.5/min -> 41.2 +- 3.6 (N=4;
// N=8 gave +- 2.8 but felt too slow: a 40->55 step takes 7 strokes vs 4).
constexpr int SMOOTH_N = 4;
constexpr uint32_t PAUSE_MS = 2500;     // longer interval = pause, not a stroke rate
constexpr float PULL = 0.05f;           // fraction of the drift corrected per stroke
constexpr uint32_t MAX_DRIFT_MS = 5000; // safety: resync if it still drifts this far
uint32_t intervals[SMOOTH_N];
int intervalCount = 0;
uint32_t lastStrokeMs = 0;
uint32_t reportedMs = 0;

uint32_t smoothedInterval()
{
    int n = intervalCount < SMOOTH_N ? intervalCount : SMOOTH_N;
    uint32_t sum = 0, lo = UINT32_MAX, hi = 0;
    for (int i = 0; i < n; i++) {
        sum += intervals[i];
        if (intervals[i] < lo) lo = intervals[i];
        if (intervals[i] > hi) hi = intervals[i];
    }
    if (n >= 4) return (sum - lo - hi) / (n - 2);
    return sum / n;
}

// Returns the stroke time to report (ms).
uint32_t smoothStroke(uint32_t strokeMs)
{
    uint32_t interval = strokeMs - lastStrokeMs;
    bool first = (crankRevs == 0) || interval >= PAUSE_MS;
    lastStrokeMs = strokeMs;
    if (first) {
        intervalCount = 0;
        reportedMs = strokeMs;
        return reportedMs;
    }
    intervals[intervalCount % SMOOTH_N] = interval;
    intervalCount++;
    uint32_t predicted = reportedMs + smoothedInterval();
    int32_t error = (int32_t)(strokeMs - predicted);
    reportedMs = predicted + (int32_t)(PULL * error);
    int32_t drift = (int32_t)(reportedMs - strokeMs);
    if (drift > (int32_t)MAX_DRIFT_MS || drift < -(int32_t)MAX_DRIFT_MS) {
        reportedMs = strokeMs;
    }
    return reportedMs;
}
bool streaming[MAX_CONNECTIONS] = {false};
uint32_t ledOffAt = 0;

// Battery percentage from open-circuit voltage (Meshtastic's OCV table for
// the WisMesh Tag: 100 %, 90 %, ... 0 %).
uint8_t batteryPercent(uint16_t mv)
{
    static const uint16_t ocv[] = {4160, 4020, 3940, 3870, 3810, 3760, 3740, 3720, 3680, 3620, 2990};
    if (mv >= ocv[0]) return 100;
    for (int i = 1; i < 11; i++) {
        if (mv >= ocv[i]) {
            return (uint8_t)(100 - 10 * i + 10 * (mv - ocv[i]) / (ocv[i - 1] - ocv[i]));
        }
    }
    return 0;
}

uint8_t connectionCount()
{
    uint8_t n = 0;
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) n += Bluefruit.connected(h);
    return n;
}

void onConnect(uint16_t conn_hdl)
{
    // No PHY / data-length / MTU requests here: bike computers may drop the
    // link over them; phones negotiate a large MTU themselves.
    BLEConnection *conn = Bluefruit.Connection(conn_hdl);
    char peer[32] = {0};
    conn->getPeerName(peer, sizeof peer);
    Serial.printf("# BLE connected [%u] %s, interval %u x 1.25 ms\n", conn_hdl, peer, conn->getConnectionInterval());
    if (connectionCount() < MAX_CONNECTIONS) {
        Bluefruit.Advertising.start(0);
    }
}

void onDisconnect(uint16_t conn_hdl, uint8_t reason)
{
    if (conn_hdl < MAX_CONNECTIONS) streaming[conn_hdl] = false;
    Serial.printf("# BLE disconnected [%u], reason 0x%02X\n", conn_hdl, reason);
}

// Text to every UART subscriber and to USB serial.
void output(const char *text)
{
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        if (streaming[h]) bleuart.write(h, (const uint8_t *)text, strlen(text));
    }
    if (Serial) Serial.print(text);
}

void notifyCsc()
{
    uint8_t data[5] = {
        CSC_FLAG_CRANK_DATA,
        (uint8_t)(crankRevs & 0xFF),
        (uint8_t)(crankRevs >> 8),
        (uint8_t)(lastCrankEventTime & 0xFF),
        (uint8_t)(lastCrankEventTime >> 8),
    };
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        if (Bluefruit.connected(h) && cscMeasurement.notifyEnabled(h)) {
            cscMeasurement.notify(h, data, sizeof data);
        }
    }
}

void setupBle()
{
    Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
    Bluefruit.begin(MAX_CONNECTIONS, 0);
    Bluefruit.setName("Paddle Stroke");
    Bluefruit.setAppearance(APPEARANCE_CADENCE_SENSOR);
    Bluefruit.setTxPower(4);
    Bluefruit.autoConnLed(false); // blue LED off (power)
    Bluefruit.Periph.setConnectCallback(onConnect);
    Bluefruit.Periph.setDisconnectCallback(onDisconnect);

    deviceInfo.setManufacturer("DIY");
    deviceInfo.setModel("Paddle Stroke (WisMesh Tag)");
    deviceInfo.begin();
    battery.begin();
    battery.write(batteryPercent(batteryMillivolts()));

    cscService.begin();
    cscMeasurement.setProperties(CHR_PROPS_NOTIFY);
    cscMeasurement.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    cscMeasurement.setMaxLen(5);
    cscMeasurement.begin();
    cscFeature.setProperties(CHR_PROPS_READ);
    cscFeature.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    cscFeature.setFixedLen(2);
    cscFeature.begin();
    cscFeature.write16(CSC_FEATURE_CRANK);
    sensorLocation.setProperties(CHR_PROPS_READ);
    sensorLocation.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    sensorLocation.setFixedLen(1);
    sensorLocation.begin();
    sensorLocation.write8(SENSOR_LOCATION_OTHER);

    bleuart.begin();

    Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
    Bluefruit.Advertising.addAppearance(APPEARANCE_CADENCE_SENSOR);
    Bluefruit.Advertising.addService(cscService);
    Bluefruit.Advertising.addName();
    Bluefruit.ScanResponse.addService(bleuart);
    Bluefruit.Advertising.restartOnDisconnect(true);
    Bluefruit.Advertising.setInterval(32, 244);
    Bluefruit.Advertising.setFastTimeout(30);
    Bluefruit.Advertising.start(0);
}

void setup()
{
    pinMode(LED_GREEN, OUTPUT);
    // GNSS off: it sits on the switched 3.3 V rail; the accelerometer does not (t_rail test).
    digitalWrite(PIN_3V3_EN, LOW);

    Serial.begin(115200);
    while (!Serial && millis() < 2000) delay(10);
    Serial.println("# Paddle Stroke: milestone 5 (stroke detector + cadence)");

    Wire.begin();
    Wire.setClock(400000);
    if (!accel.begin(Wire)) {
        while (true) { // fast blink forever = accelerometer not found
            Serial.println("# ERROR: LIS2DH not found");
            digitalToggle(LED_GREEN);
            delayPolling(100);
        }
    }
    accel.configure(LIS2DH::ODR_100HZ, true);
    setupBle();
    Serial.println("# advertising as \"Paddle Stroke\"");
}

void loop()
{
    uint32_t now = millis();

    // UART subscribers get a header when they subscribe.
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        bool want = Bluefruit.connected(h) && bleuart.notifyEnabled(h);
        if (want && !streaming[h]) {
            streaming[h] = true;
            char hdr[160];
            snprintf(hdr, sizeof hdr,
                     "# Paddle Stroke, 100 Hz, +-4 g, uptime %lu ms\n# battery t_ms=%lu mv=%u\nseq,t_ms,x_mg,y_mg,z_mg\n",
                     (unsigned long)now, (unsigned long)now, batteryMillivolts());
            bleuart.write(h, (const uint8_t *)hdr, strlen(hdr));
        } else if (!want) {
            streaming[h] = false;
        }
    }

    // Drain the FIFO: raw lines out, samples into the detector.
    bool overrun = false;
    uint8_t n = accel.fifoCount(&overrun);
    if (overrun) {
        char msg[48];
        snprintf(msg, sizeof msg, "# FIFO overrun before seq %lu\n", (unsigned long)detector.samples());
        output(msg);
    }
    static char buf[32 * 40 + 64];
    size_t len = 0;
    for (uint8_t i = 0; i < n; i++) {
        AccelSample s;
        if (!accel.read(s)) break;
        uint32_t seq = detector.samples();
        uint32_t t = now - (uint32_t)(n - 1 - i) * SAMPLE_PERIOD_MS; // newest sample taken "now"
        len += snprintf(buf + len, sizeof buf - len, "%lu,%lu,%d,%d,%d\n", (unsigned long)seq, (unsigned long)t,
                        s.x_mg, s.y_mg, s.z_mg);
        if (detector.update(s.x_mg / 1000.0f, s.y_mg / 1000.0f, s.z_mg / 1000.0f)) {
            uint32_t strokeSeq = detector.strokeSample();
            uint32_t strokeMs = now - (uint32_t)(detector.samples() - 1 - strokeSeq) * SAMPLE_PERIOD_MS;
            uint32_t reported = smoothStroke(strokeMs);
            crankRevs++;
            lastCrankEventTime = (uint16_t)(((uint64_t)reported * 1024) / 1000);
            len += snprintf(buf + len, sizeof buf - len, "# stroke n=%lu seq=%lu t_ms=%lu\n",
                            (unsigned long)detector.strokes(), (unsigned long)strokeSeq, (unsigned long)strokeMs);
            digitalWrite(LED_GREEN, LED_STATE_ON);
            ledOffAt = now + LED_BLINK_MS;
        }
    }
    if (len > 0) output(buf);

    static uint32_t lastCsc = 0;
    if (now - lastCsc >= CSC_EVERY_MS) {
        lastCsc = now;
        notifyCsc();
    }

    static uint32_t lastBattery = 0;
    if (now - lastBattery >= BATTERY_EVERY_MS) {
        lastBattery = now;
        uint16_t mv = batteryMillivolts();
        battery.write(batteryPercent(mv));
        char msg[48];
        snprintf(msg, sizeof msg, "# battery t_ms=%lu mv=%u\n", (unsigned long)now, mv);
        output(msg);
    }

    static uint32_t lastHeartbeat = 0;
    if (now - lastHeartbeat >= HEARTBEAT_MS) {
        lastHeartbeat = now;
        digitalWrite(LED_GREEN, LED_STATE_ON);
        ledOffAt = now + LED_BLINK_MS;
    }

    if (ledOffAt && (int32_t)(now - ledOffAt) >= 0) {
        digitalWrite(LED_GREEN, !LED_STATE_ON);
        ledOffAt = 0;
    }
    delayPolling(POLL_MS);
}
