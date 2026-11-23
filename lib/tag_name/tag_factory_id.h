// Firmware side of tag_name: the factory device address and the BLE name.
// Not used by the host test (needs the nRF52 registers and Bluefruit).
#pragma once

#include <bluefruit.h>

#include "tag_name.h"

// The chip's factory device address, read from FICR rather than from the
// Bluetooth stack, so a custom address or privacy mode can never rename a Tag.
// Least significant byte first.
inline void tag_factory_id(uint8_t id[6]) {
    uint32_t lo = NRF_FICR->DEVICEADDR[0];
    uint32_t hi = NRF_FICR->DEVICEADDR[1];
    for (int i = 0; i < 4; i++) id[i] = (lo >> (8 * i)) & 0xFF;
    id[4] = hi & 0xFF;
    id[5] = (hi >> 8) & 0xFF;
}

// Call after Bluefruit.begin(): sets the advertised name ("<prefix> honu_A")
// and fills name and addr (the address phones see).
inline void tag_apply_name(const char* prefix, char* name, size_t name_n, char* addr, size_t addr_n) {
    uint8_t id[6];
    tag_factory_id(id);
    tag_ble_name(prefix, id, name, name_n);
    Bluefruit.setName(name);
    uint8_t mac[6];
    Bluefruit.getAddr(mac);
    tag_addr_string(mac, addr, addr_n);
}
