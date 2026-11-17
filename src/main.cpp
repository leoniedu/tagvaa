// Milestone 1: USB serial "hello" + LED blink.
#include <Arduino.h>
#include <Adafruit_TinyUSB.h> // USB CDC serial; the include makes PlatformIO link the library

uint32_t count = 0;

void setup()
{
    pinMode(LED_GREEN, OUTPUT);
    pinMode(LED_BLUE, OUTPUT);

    Serial.begin(115200);
    // Wait up to 3 s for the USB serial port to be opened, so the first lines aren't lost.
    while (!Serial && millis() < 3000) {
        delay(10);
    }
    Serial.println("OC6 Stroke: hello from the WisMesh Tag");
}

void loop()
{
    // Green and blue alternate once per second.
    bool phase = count % 2;
    digitalWrite(LED_GREEN, phase ? LED_STATE_ON : !LED_STATE_ON);
    digitalWrite(LED_BLUE, phase ? !LED_STATE_ON : LED_STATE_ON);

    Serial.printf("tick %lu  uptime %lu ms\n", (unsigned long)count, (unsigned long)millis());
    count++;
    delay(1000);
}
