// Milestone 3: BLE Cycling Speed and Cadence sensor with a FIXED 60 rpm.
// Go/no-go test with nRF Connect and the COOSPO CS300.
#include <Adafruit_TinyUSB.h>
#include <Arduino.h>
#include <bluefruit.h>
#include <dfu_escape.h>

constexpr uint16_t APPEARANCE_CADENCE_SENSOR = 0x0483;
constexpr uint8_t CSC_FLAG_CRANK_DATA = 0x02;
constexpr uint16_t CSC_FEATURE_CRANK = 0x0002;
constexpr uint8_t SENSOR_LOCATION_OTHER = 0x00;

BLEService cscService(UUID16_SVC_CYCLING_SPEED_AND_CADENCE);   // 0x1816
BLECharacteristic cscMeasurement(UUID16_CHR_CSC_MEASUREMENT);  // 0x2A5B
BLECharacteristic cscFeature(UUID16_CHR_CSC_FEATURE);          // 0x2A5C
BLECharacteristic sensorLocation(UUID16_CHR_SENSOR_LOCATION);  // 0x2A5D
BLEDis deviceInfo;
BLEBas battery;

// Cadence state: cumulative revolutions and time of the last revolution (1/1024 s).
// Both wrap at 65536, as the CSC spec expects.
uint16_t crankRevs = 0;
uint16_t lastCrankEventTime = 0;

void setupCsc()
{
    cscService.begin();

    cscMeasurement.setProperties(CHR_PROPS_NOTIFY);
    cscMeasurement.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    cscMeasurement.setMaxLen(5); // flags(1) + revs(2) + event time(2)
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
}

void startAdvertising()
{
    Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
    Bluefruit.Advertising.addTxPower();
    Bluefruit.Advertising.addAppearance(APPEARANCE_CADENCE_SENSOR);
    Bluefruit.Advertising.addService(cscService);
    Bluefruit.Advertising.addName();

    Bluefruit.Advertising.restartOnDisconnect(true);
    Bluefruit.Advertising.setInterval(32, 244); // fast 20 ms, then slow 152.5 ms (units of 0.625 ms)
    Bluefruit.Advertising.setFastTimeout(30);   // seconds of fast advertising
    Bluefruit.Advertising.start(0);             // advertise forever
}

void onConnect(uint16_t conn)
{
    char peer[32] = {0};
    Bluefruit.Connection(conn)->getPeerName(peer, sizeof peer);
    Serial.printf("connected: %s\n", peer);
}

void onDisconnect(uint16_t conn, uint8_t reason)
{
    Serial.printf("disconnected, reason 0x%02X\n", reason);
}

void setup()
{
    pinMode(LED_GREEN, OUTPUT);
    Serial.begin(115200);
    while (!Serial && millis() < 3000) {
        delay(10);
    }
    Serial.println("tagvaa: milestone 3 (CSC, fixed 60 rpm)");

    Bluefruit.begin();
    Bluefruit.setName("tagvaa");
    Bluefruit.setAppearance(APPEARANCE_CADENCE_SENSOR);
    Bluefruit.setTxPower(4); // dBm; max for nRF52840 is 8
    Bluefruit.autoConnLed(true); // blue LED blinks while advertising, solid when connected
    Bluefruit.Periph.setConnectCallback(onConnect);
    Bluefruit.Periph.setDisconnectCallback(onDisconnect);

    deviceInfo.setManufacturer("DIY");
    deviceInfo.setModel("tagvaa (WisMesh Tag)");
    deviceInfo.begin();

    battery.begin();
    battery.write(100); // placeholder until we read the battery pin

    setupCsc();
    startAdvertising();
    Serial.println("advertising as \"tagvaa\"");
}

void loop()
{
    // One crank revolution per second = 60 rpm.
    crankRevs++;
    lastCrankEventTime += 1024;

    uint8_t data[5] = {
        CSC_FLAG_CRANK_DATA,
        (uint8_t)(crankRevs & 0xFF),
        (uint8_t)(crankRevs >> 8),
        (uint8_t)(lastCrankEventTime & 0xFF),
        (uint8_t)(lastCrankEventTime >> 8),
    };

    if (Bluefruit.connected() && cscMeasurement.notifyEnabled()) {
        cscMeasurement.notify(data, sizeof data);
    }
    Serial.printf("revs %u  event_time %u\n", crankRevs, lastCrankEventTime);

    digitalWrite(LED_GREEN, LED_STATE_ON); // short green flash per "stroke"
    delayPolling(50);
    digitalWrite(LED_GREEN, !LED_STATE_ON);
    delayPolling(950);
}
