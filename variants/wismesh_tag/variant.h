// Pin map for the RAK WisMesh Tag (RAK4630 = nRF52840 + SX1262).
// Source: meshtastic/firmware variants/nrf52840/rak_wismeshtag/variant.h @ 6d41e27.
// Only the pins this project uses are kept. Arduino pin N == nRF GPIO N
// (P0.x = x, P1.x = 32 + x), see g_ADigitalPinMap in variant.cpp.

#ifndef _VARIANT_WISMESH_TAG_
#define _VARIANT_WISMESH_TAG_

#define VARIANT_MCK (64000000ul)
#define USE_LFXO // board has a 32 kHz crystal

#include "WVariant.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PINS_COUNT (48)
#define NUM_DIGITAL_PINS (48)
#define NUM_ANALOG_INPUTS (6)
#define NUM_ANALOG_OUTPUTS (0)

// LEDs (active high). The red LED is hard-wired to the charger, not the MCU.
#define PIN_LED1 (35)  // P1.03 green
#define PIN_LED2 (36)  // P1.04 blue
#define LED_GREEN PIN_LED1
#define LED_BLUE PIN_LED2 // Bluefruit blinks this while advertising
#define LED_STATE_ON 1

// Front user button (the back button is reset / DFU, not a GPIO)
#define PIN_BUTTON1 (9) // P0.09, needs internal pull-up

// Analog
#define PIN_A0 (5) // battery sense (divider 0.6 * VBAT)
#define PIN_A1 (31)
#define PIN_A2 (28)
#define PIN_A3 (29)
#define PIN_A4 (30)
#define PIN_A5 (31)
#define PIN_A6 (0xff)
#define PIN_A7 (0xff)
static const uint8_t A0 = PIN_A0;
static const uint8_t A1 = PIN_A1;
static const uint8_t A2 = PIN_A2;
static const uint8_t A3 = PIN_A3;
static const uint8_t A4 = PIN_A4;
static const uint8_t A5 = PIN_A5;
static const uint8_t A6 = PIN_A6;
static const uint8_t A7 = PIN_A7;
#define ADC_RESOLUTION 14
#define PIN_AREF (2)
static const uint8_t AREF = PIN_AREF;
#define PIN_NFC1 (9)
#define PIN_NFC2 (10)

// UART to the GNSS module
#define PIN_SERIAL1_RX (15)
#define PIN_SERIAL1_TX (16)

// SPI (SX1262 LoRa radio, unused here)
#define SPI_INTERFACES_COUNT 1
#define PIN_SPI_MISO (45)
#define PIN_SPI_MOSI (44)
#define PIN_SPI_SCK (43)
static const uint8_t SS = 42;
static const uint8_t MOSI = PIN_SPI_MOSI;
static const uint8_t MISO = PIN_SPI_MISO;
static const uint8_t SCK = PIN_SPI_SCK;

// I2C (accelerometer)
#define WIRE_INTERFACES_COUNT 1
#define PIN_WIRE_SDA (25) // P0.25
#define PIN_WIRE_SCL (24) // P0.24

// 3.3 V peripheral rail (GNSS, sensors). Meshtastic drives this HIGH at boot.
#define PIN_3V3_EN (34) // P1.02

#define PIN_BUZZER (21)
#define SX126X_POWER_EN (37)

#ifdef __cplusplus
}
#endif

#endif
