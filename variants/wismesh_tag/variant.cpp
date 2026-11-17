// Source: meshtastic/firmware variants/nrf52840/rak_wismeshtag/variant.cpp @ 6d41e27
// (Meshtastic's low-voltage System OFF hook is left out).

#include "variant.h"
#include "nrf.h"
#include "wiring_constants.h"
#include "wiring_digital.h"

// Identity map: Arduino pin N is nRF GPIO N.
const uint32_t g_ADigitalPinMap[] = {
    // P0
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    // P1
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47};

void initVariant()
{
    pinMode(PIN_LED1, OUTPUT);
    digitalWrite(PIN_LED1, !LED_STATE_ON);
    pinMode(PIN_LED2, OUTPUT);
    digitalWrite(PIN_LED2, !LED_STATE_ON);

    // Power the 3.3 V peripheral rail, as Meshtastic does.
    pinMode(PIN_3V3_EN, OUTPUT);
    digitalWrite(PIN_3V3_EN, HIGH);
}
