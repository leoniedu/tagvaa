#include "lis2dh.h"

namespace
{
constexpr uint8_t REG_WHO_AM_I = 0x0F;
constexpr uint8_t REG_CTRL_REG1 = 0x20;
constexpr uint8_t REG_CTRL_REG4 = 0x23;
constexpr uint8_t REG_CTRL_REG5 = 0x24;
constexpr uint8_t REG_OUT_X_L = 0x28;
constexpr uint8_t REG_FIFO_CTRL = 0x2E;
constexpr uint8_t REG_FIFO_SRC = 0x2F;

constexpr uint8_t AUTO_INCREMENT = 0x80; // MSB of the sub-address enables multi-byte reads

// ±4 g, high-resolution: 12-bit left-justified data, 2 mg per digit.
constexpr int16_t MG_PER_DIGIT = 2;
} // namespace

bool LIS2DH::begin(TwoWire &wire)
{
    wire_ = &wire;
    const uint8_t candidates[] = {0x18, 0x19};
    for (uint8_t candidate : candidates) {
        addr_ = candidate;
        if (whoAmI() == WHO_AM_I_VALUE) {
            return true;
        }
    }
    addr_ = 0;
    return false;
}

uint8_t LIS2DH::whoAmI()
{
    uint8_t v = 0;
    readRegs(REG_WHO_AM_I, &v, 1);
    return v;
}

bool LIS2DH::configure(Odr odr, bool useFifo)
{
    bool ok = true;
    // ODR, normal power (LPen = 0), X/Y/Z enabled.
    ok &= writeReg(REG_CTRL_REG1, (odr << 4) | 0x07);
    // BDU = 1 (no torn reads), FS = ±4 g, HR = 1 (high resolution).
    ok &= writeReg(REG_CTRL_REG4, 0x80 | 0x10 | 0x08);
    // FIFO_EN, then bypass first (clears the FIFO), then stream mode.
    ok &= writeReg(REG_CTRL_REG5, useFifo ? 0x40 : 0x00);
    ok &= writeReg(REG_FIFO_CTRL, 0x00);
    if (useFifo) {
        ok &= writeReg(REG_FIFO_CTRL, 0x80);
    }
    return ok;
}

bool LIS2DH::read(AccelSample &s)
{
    uint8_t b[6];
    if (!readRegs(REG_OUT_X_L | AUTO_INCREMENT, b, sizeof b)) {
        return false;
    }
    // 12-bit values are left-justified in 16 bits: shift right by 4 (arithmetic).
    s.x_mg = (int16_t)(b[0] | (b[1] << 8)) >> 4;
    s.y_mg = (int16_t)(b[2] | (b[3] << 8)) >> 4;
    s.z_mg = (int16_t)(b[4] | (b[5] << 8)) >> 4;
    s.x_mg *= MG_PER_DIGIT;
    s.y_mg *= MG_PER_DIGIT;
    s.z_mg *= MG_PER_DIGIT;
    return true;
}

uint8_t LIS2DH::fifoCount(bool *overrun)
{
    uint8_t src = 0;
    readRegs(REG_FIFO_SRC, &src, 1);
    if (overrun) {
        *overrun = src & 0x40;
    }
    // FSS[4:0] counts unread samples; when the FIFO is completely full OVRN is set and FSS reads 31,
    // so report 32 in that case.
    return (src & 0x40) ? 32 : (src & 0x1F);
}

bool LIS2DH::writeReg(uint8_t reg, uint8_t value)
{
    wire_->beginTransmission(addr_);
    wire_->write(reg);
    wire_->write(value);
    return wire_->endTransmission() == 0;
}

bool LIS2DH::readRegs(uint8_t reg, uint8_t *buf, uint8_t len)
{
    wire_->beginTransmission(addr_);
    wire_->write(reg);
    if (wire_->endTransmission(false) != 0) {
        return false;
    }
    if (wire_->requestFrom(addr_, len) != len) {
        return false;
    }
    for (uint8_t i = 0; i < len; i++) {
        buf[i] = wire_->read();
    }
    return true;
}
