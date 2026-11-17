// Ways back into the UF2 bootloader without the reset button:
//   - send "dfu" + Enter over USB serial
//   - hold the front button for 5 s
// Call dfuEscapePoll() often from loop().
#pragma once

#include <Arduino.h>

inline void dfuEscapePoll()
{
    static char line[8];
    static uint8_t len = 0;
    static uint32_t pressedSince = 0;

    while (Serial.available()) {
        char c = Serial.read();
        if (c == '\r' || c == '\n') {
            line[len] = '\0';
            if (strcmp(line, "dfu") == 0) {
                Serial.println("# rebooting into UF2 bootloader");
                Serial.flush();
                delay(100);
                enterUf2Dfu();
            }
            len = 0;
        } else if (len < sizeof line - 1) {
            line[len++] = c;
        }
    }

    static bool buttonInit = false;
    if (!buttonInit) {
        pinMode(PIN_BUTTON1, INPUT_PULLUP);
        buttonInit = true;
    }
    if (digitalRead(PIN_BUTTON1) == LOW) { // active low
        if (pressedSince == 0) {
            pressedSince = millis() | 1;
        } else if (millis() - pressedSince > 5000) {
            enterUf2Dfu();
        }
    } else {
        pressedSince = 0;
    }
}

// delay() that keeps checking for the escape gestures.
inline void delayPolling(uint32_t ms)
{
    uint32_t start = millis();
    while (millis() - start < ms) {
        dfuEscapePoll();
        delay(10);
    }
}
