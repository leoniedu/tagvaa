// Milestone 2: I2C scan, LIS2DH WHO_AM_I, raw x/y/z at 10 Hz over USB serial.
#include <Adafruit_TinyUSB.h>
#include <Arduino.h>
#include <Wire.h>
#include <dfu_escape.h>
#include <lis2dh.h>

LIS2DH accel;
bool accelOk = false;

void scanI2C()
{
    Serial.println("I2C scan:");
    int found = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.printf("  device at 0x%02X\n", addr);
            found++;
        }
    }
    Serial.printf("  %d device(s) found\n", found);
}

void setup()
{
    pinMode(LED_GREEN, OUTPUT);
    Serial.begin(115200);
    while (!Serial && millis() < 5000) {
        delay(10);
    }
    Serial.println("tagvaa: milestone 2 (accelerometer)");

    delay(50); // let the 3.3 V rail (enabled in initVariant) settle
    Wire.begin();
    Wire.setClock(400000);
    scanI2C();

    accelOk = accel.begin(Wire);
    if (accelOk) {
        Serial.printf("LIS2DH at 0x%02X, WHO_AM_I = 0x%02X (expected 0x33)\n", accel.address(), accel.whoAmI());
        accel.configure(LIS2DH::ODR_10HZ, false);
        Serial.println("x_mg,y_mg,z_mg");
    } else {
        Serial.println("LIS2DH NOT found at 0x18/0x19");
    }
}

void loop()
{
    if (!accelOk) {
        // Fast blink = error.
        digitalToggle(LED_GREEN);
        delayPolling(100);
        return;
    }
    AccelSample s;
    if (accel.read(s)) {
        Serial.printf("%d,%d,%d\n", s.x_mg, s.y_mg, s.z_mg);
    }
    digitalToggle(LED_GREEN);
    delayPolling(100); // 10 Hz
}
