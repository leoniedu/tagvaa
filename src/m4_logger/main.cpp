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
#include <dfu_escape.h>
#include <lis2dh.h>

constexpr uint32_t SAMPLE_PERIOD_MS = 10; // 100 Hz
constexpr uint32_t POLL_MS = 50;          // read the FIFO every 50 ms (~5 samples); FIFO holds 32 (320 ms)

LIS2DH accel;
BLEUart bleuart;
BLEDis deviceInfo;

// Two connections, so a device that auto-reconnects (e.g. a bike computer
// paired with this Tag earlier) can't lock the phone out.
constexpr uint8_t MAX_CONNECTIONS = 2;

uint32_t seq = 0;
bool streaming[MAX_CONNECTIONS] = {false};

uint8_t connectionCount()
{
    uint8_t n = 0;
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        n += Bluefruit.connected(h);
    }
    return n;
}

void onConnect(uint16_t conn_hdl)
{
    BLEConnection *conn = Bluefruit.Connection(conn_hdl);
    // Ask for big packets and a short connection interval; the phone decides what it grants.
    conn->requestPHY();
    conn->requestDataLengthUpdate();
    conn->requestMtuExchange(247);
    conn->requestConnectionParameter(12); // 12 x 1.25 ms = 15 ms

    char peer[32] = {0};
    conn->getPeerName(peer, sizeof peer);
    Serial.printf("# BLE connected [%u] %s\n", conn_hdl, peer);

    // Advertising stops on connect; keep it going while a slot is free.
    if (connectionCount() < MAX_CONNECTIONS) {
        Bluefruit.Advertising.start(0);
    }
}

void onDisconnect(uint16_t conn_hdl, uint8_t reason)
{
    if (conn_hdl < MAX_CONNECTIONS) {
        streaming[conn_hdl] = false;
    }
    Serial.printf("# BLE disconnected [%u], reason 0x%02X\n", conn_hdl, reason);
}

// Sends text to every connection that subscribed to the UART, and to USB serial.
void output(const char *text)
{
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        if (streaming[h]) {
            bleuart.write(h, (const uint8_t *)text, strlen(text));
        }
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
    Serial.println("# Paddle Logger: milestone 4 (100 Hz logger)");

    delay(50);
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

    Bluefruit.configPrphBandwidth(BANDWIDTH_MAX); // MTU up to 247; must precede begin()
    Bluefruit.begin(MAX_CONNECTIONS, 0);
    Bluefruit.setName("Paddle Logger");
    Bluefruit.setTxPower(4);
    Bluefruit.autoConnLed(true);
    Bluefruit.Periph.setConnectCallback(onConnect);
    Bluefruit.Periph.setDisconnectCallback(onDisconnect);

    deviceInfo.setManufacturer("DIY");
    deviceInfo.setModel("Paddle Logger (WisMesh Tag)");
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

    Serial.println("# advertising as \"Paddle Logger\"");
    Serial.println("seq,t_ms,x_mg,y_mg,z_mg");
}

void loop()
{
    // Start streaming to a connection when it subscribes to the UART TX characteristic.
    for (uint16_t h = 0; h < MAX_CONNECTIONS; h++) {
        bool want = Bluefruit.connected(h) && bleuart.notifyEnabled(h);
        if (want && !streaming[h]) {
            streaming[h] = true;
            char hdr[96];
            snprintf(hdr, sizeof hdr, "# Paddle Logger, 100 Hz, +-4 g, uptime %lu ms\nseq,t_ms,x_mg,y_mg,z_mg\n",
                     (unsigned long)millis());
            bleuart.write(h, (const uint8_t *)hdr, strlen(hdr));
            Serial.printf("# streaming to [%u]\n", h);
        } else if (!want) {
            streaming[h] = false;
        }
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
    delayPolling(POLL_MS);
}
