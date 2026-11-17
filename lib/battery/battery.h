// Tag battery voltage. Divider and calibration from Meshtastic's rak_wismeshtag
// variant: BAT_ADC = 0.6 x VBAT (1 M / 1.5 M), 3.0 V internal reference,
// 12-bit, ADC_MULTIPLIER 1.73 (their calibrated value, slightly above 1/0.6).
#pragma once

#include <Arduino.h>

inline uint16_t batteryMillivolts()
{
    analogReference(AR_INTERNAL_3_0);
    analogReadResolution(12);
    uint32_t sum = 0;
    for (int i = 0; i < 8; i++) {
        sum += analogRead(PIN_A0);
    }
    float adc = sum / 8.0f;
    return (uint16_t)(adc * 3000.0f / 4096.0f * 1.73f);
}
