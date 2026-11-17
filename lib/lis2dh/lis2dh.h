// Minimal LIS2DH accelerometer driver (I2C), high-resolution (12-bit) mode only.
// Register map: ST LIS2DH datasheet (DocID 023591).
#pragma once

#include <Arduino.h>
#include <Wire.h>

struct AccelSample {
    int16_t x_mg;
    int16_t y_mg;
    int16_t z_mg;
};

class LIS2DH
{
  public:
    static constexpr uint8_t WHO_AM_I_VALUE = 0x33;

    // Output data rates (CTRL_REG1 ODR field).
    enum Odr : uint8_t { ODR_10HZ = 0x2, ODR_25HZ = 0x3, ODR_50HZ = 0x4, ODR_100HZ = 0x5, ODR_200HZ = 0x6 };

    // Looks for the chip at 0x18 and 0x19 and checks WHO_AM_I. Returns true if found.
    bool begin(TwoWire &wire = Wire);

    // ±4 g full scale, high-resolution mode, all axes on. With useFifo the 32-sample
    // FIFO runs in stream mode, so the host can read in bursts without losing samples.
    bool configure(Odr odr, bool useFifo);

    uint8_t address() const { return addr_; }
    uint8_t whoAmI();

    // Reads one sample (oldest in FIFO when FIFO is on).
    bool read(AccelSample &s);

    // Number of unread samples in the FIFO (0..32). Sets overrun if samples were lost.
    uint8_t fifoCount(bool *overrun = nullptr);

  private:
    bool writeReg(uint8_t reg, uint8_t value);
    bool readRegs(uint8_t reg, uint8_t *buf, uint8_t len);

    TwoWire *wire_ = nullptr;
    uint8_t addr_ = 0;
};
