// Test: what is on the switched 3.3 V rail (PIN_3V3_EN)?
//
// 1. With the rail ON and then OFF, scan I2C, read the LIS2DH WHO_AM_I and
//    count GNSS bytes on Serial1 (NMEA at 9600 baud) for 3 s.
// 2. Then toggle the rail every 30 s and print the state, so a USB power
//    meter can show the current difference (Tag battery should be full).
#include <Adafruit_TinyUSB.h>
#include <Arduino.h>
#include <Wire.h>
#include <battery.h>
#include <dfu_escape.h>
#include <lis2dh.h>

LIS2DH accel;

void setRail(bool on)
{
    digitalWrite(PIN_3V3_EN, on ? HIGH : LOW);
    if (!on) {
        // Don't feed the unpowered GNSS through its UART pins.
        Serial1.end();
    }
    delayPolling(500);
}

int scanI2C()
{
    int found = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.printf("  I2C device at 0x%02X\n", addr);
            found++;
        }
    }
    return found;
}

uint32_t gnssBytes(uint32_t ms)
{
    Serial1.begin(9600);
    uint32_t n = 0;
    uint32_t start = millis();
    char sample[60] = {0};
    while (millis() - start < ms) {
        while (Serial1.available()) {
            char c = Serial1.read();
            if (n < sizeof sample - 1) {
                sample[n] = (c == '\r' || c == '\n') ? ' ' : c;
            }
            n++;
        }
        dfuEscapePoll();
        delay(5);
    }
    Serial.printf("  GNSS: %lu bytes in %lu ms  \"%s\"\n", (unsigned long)n, (unsigned long)ms, sample);
    return n;
}

// With the rail off the I2C pull-ups may be unpowered; a bus held low can hang
// the I2C driver (and with it the "dfu" escape), so look at the lines first.
bool busLinesHigh()
{
    Wire.end();
    pinMode(PIN_WIRE_SDA, INPUT);
    pinMode(PIN_WIRE_SCL, INPUT);
    delay(5);
    bool sda = digitalRead(PIN_WIRE_SDA), scl = digitalRead(PIN_WIRE_SCL);
    Serial.printf("  I2C lines: SDA %s, SCL %s\n", sda ? "high" : "LOW", scl ? "high" : "LOW");
    if (sda && scl) {
        Wire.begin();
        Wire.setClock(100000);
    }
    return sda && scl;
}

void report(const char *label)
{
    Serial.printf("rail %s:\n", label);
    if (!busLinesHigh()) {
        Serial.println("  skipping I2C (pull-ups unpowered: the accelerometer bus is on this rail)");
        gnssBytes(3000);
        Serial.printf("  battery %u mV\n", batteryMillivolts());
        return;
    }
    int devices = scanI2C();
    bool lis = accel.begin(Wire);
    Serial.printf("  %d I2C device(s); LIS2DH %s", devices, lis ? "answers" : "NOT found");
    if (lis) {
        AccelSample s;
        accel.configure(LIS2DH::ODR_10HZ, false);
        delay(300);
        accel.read(s);
        Serial.printf(" (x %d, y %d, z %d mg)", s.x_mg, s.y_mg, s.z_mg);
    }
    Serial.println();
    gnssBytes(3000);
    Serial.printf("  battery %u mV\n", batteryMillivolts());
}

void setup()
{
    Serial.begin(115200);
    while (!Serial && millis() < 5000) {
        delay(10);
    }
    Serial.println("# Paddle test: 3.3 V rail (PIN_3V3_EN)");
    Wire.begin();
    Wire.setClock(100000);

    setRail(true);
    report("ON");
    setRail(false);
    report("OFF");
    setRail(true);
    report("ON again");
    Serial.println("# now toggling the rail every 30 s (watch a USB power meter)");
}

void loop()
{
    static bool on = true;
    on = !on;
    setRail(on);
    Serial.printf("rail %s  battery %u mV  uptime %lu s\n", on ? "ON " : "OFF", batteryMillivolts(),
                  (unsigned long)(millis() / 1000));
    digitalWrite(LED_GREEN, on ? LED_STATE_ON : !LED_STATE_ON); // green = rail on
    delayPolling(29500);
}
