// Milestone 4: stream the accelerometer at 100 Hz over BLE (Nordic UART Service) as CSV.
//
// Line format:  seq,t_ms,x_mg,y_mg,z_mg
//   seq   gap-free sample counter (exact 100 Hz grid, nominal; use it for timing)
//   t_ms  MCU uptime in ms, estimated per sample (for aligning with phone/GPS clocks)
// Lines starting with '#' are comments (header info, FIFO overruns).
// The same lines are mirrored to USB serial when a terminal is open.
#include <Adafruit_TinyUSB.h>
#include <Arduino.h>
#include <Wire.h>
#include <bluefruit.h>
#include <lis2dh.h>

constexpr uint32_t SAMPLE_PERIOD_MS = 10; // 100 Hz
constexpr uint32_t POLL_MS = 50;          // read the FIFO every 50 ms (~5 samples); FIFO holds 32 (320 ms)

LIS2DH accel;
BLEUart bleuart;
BLEDis deviceInfo;

uint32_t seq = 0;
bool streaming = false;

void onConnect(uint16_t conn_hdl)
{
    BLEConnection *conn = Bluefruit.Connection(conn_hdl);
    // Ask for big packets and a short connection interval; the phone decides what it grants.
    conn->requestPHY();
    conn->requestDataLengthUpdate();
    conn->requestMtuExchange(247);
    conn->requestConnectionParameter(12); // 12 x 1.25 ms = 15 ms
    Serial.println("# BLE connected");
}

void onDisconnect(uint16_t conn_hdl, uint8_t reason)
{
    Serial.printf("# BLE disconnected, reason 0x%02X\n", reason);
}

void output(const char *text)
{
    if (streaming) {
        bleuart.write((const uint8_t *)text, strlen(text));
    }
    if (Serial) {
        Serial.print(text);
    }
}

void setup()
{
    pinMode(LED_GREEN, OUTPUT);
    Serial.begin(115200);
    while (!Serial && millis() < 2000) {
        delay(10);
    }
    Serial.println("# OC6 Stroke: milestone 4 (100 Hz logger)");

    delay(50);
    Wire.begin();
    Wire.setClock(400000);
    if (!accel.begin(Wire)) {
        while (true) { // fast blink forever = accelerometer not found
            Serial.println("# ERROR: LIS2DH not found");
            digitalToggle(LED_GREEN);
            delay(100);
        }
    }
    accel.configure(LIS2DH::ODR_100HZ, true);

    Bluefruit.configPrphBandwidth(BANDWIDTH_MAX); // MTU up to 247; must precede begin()
    Bluefruit.begin();
    Bluefruit.setName("OC6 Logger");
    Bluefruit.setTxPower(4);
    Bluefruit.autoConnLed(true);
    Bluefruit.Periph.setConnectCallback(onConnect);
    Bluefruit.Periph.setDisconnectCallback(onDisconnect);

    deviceInfo.setManufacturer("DIY");
    deviceInfo.setModel("OC6 Logger (WisMesh Tag)");
    deviceInfo.begin();
    bleuart.begin();

    Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
    Bluefruit.Advertising.addTxPower();
    Bluefruit.Advertising.addService(bleuart);
    Bluefruit.ScanResponse.addName();
    Bluefruit.Advertising.restartOnDisconnect(true);
    Bluefruit.Advertising.setInterval(32, 244);
    Bluefruit.Advertising.setFastTimeout(30);
    Bluefruit.Advertising.start(0);

    Serial.println("# advertising as \"OC6 Logger\"");
    Serial.println("seq,t_ms,x_mg,y_mg,z_mg");
}

void loop()
{
    // Start streaming when the phone subscribes to the UART TX characteristic.
    bool wantStream = Bluefruit.connected() && bleuart.notifyEnabled();
    if (wantStream && !streaming) {
        streaming = true;
        char hdr[96];
        snprintf(hdr, sizeof hdr, "# OC6 Logger, 100 Hz, +-4 g, uptime %lu ms\nseq,t_ms,x_mg,y_mg,z_mg\n",
                 (unsigned long)millis());
        output(hdr);
    } else if (!wantStream) {
        streaming = false;
    }

    uint32_t now = millis();
    bool overrun = false;
    uint8_t n = accel.fifoCount(&overrun);
    if (overrun) {
        char msg[48];
        snprintf(msg, sizeof msg, "# FIFO overrun before seq %lu\n", (unsigned long)seq);
        output(msg);
    }

    // Collect all available samples into one buffer and send it in one go.
    static char buf[32 * 40];
    size_t len = 0;
    for (uint8_t i = 0; i < n; i++) {
        AccelSample s;
        if (!accel.read(s)) {
            break;
        }
        // Oldest sample first; the newest one is assumed to be taken "now".
        uint32_t t = now - (uint32_t)(n - 1 - i) * SAMPLE_PERIOD_MS;
        len += snprintf(buf + len, sizeof buf - len, "%lu,%lu,%d,%d,%d\n", (unsigned long)seq, (unsigned long)t,
                        s.x_mg, s.y_mg, s.z_mg);
        seq++;
    }
    if (len > 0) {
        output(buf);
    }

    digitalWrite(LED_GREEN, (now / 500) % 2 ? LED_STATE_ON : !LED_STATE_ON); // slow blink = running
    delay(POLL_MS);
}
