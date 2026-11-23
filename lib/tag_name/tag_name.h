// Friendly Tag names ("tagvaa honu_A") from the chip's factory address.
// Plain C++, no Arduino: the host test compiles it on the Mac.
// id/mac bytes are least significant first.
#pragma once

#include <stddef.h>
#include <stdint.h>

// One of 64 fixed ocean words (index 0..63). The list never changes once
// shipped: reordering it would rename every Tag.
const char* tag_word(uint8_t index);

// "honu_A": word from id bits 0-5, letter A-P from id bits 6-9.
void tag_suffix(const uint8_t id[6], char* out, size_t n);

// "<prefix> honu_A", e.g. "tagvaa honu_A" or "tagvaa log honu_A".
void tag_ble_name(const char* prefix, const uint8_t id[6], char* out, size_t n);

// "C5:B5:C4:D3:E2:F1": most significant byte first.
void tag_addr_string(const uint8_t mac[6], char* out, size_t n);
