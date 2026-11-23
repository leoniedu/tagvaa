// Host test for lib/tag_name: names derived from the factory address.
// c++ -std=c++17 -I lib/tag_name lib/tag_name/tag_name.cpp test/host/tag_name_test.cpp -o .pio/tag_name_test
#include "tag_name.h"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>

static std::string suffix(uint8_t b0, uint8_t b1) {
    const uint8_t id[6] = {b0, b1, 0, 0, 0, 0};
    char out[16];
    tag_suffix(id, out, sizeof out);
    return out;
}

int main() {
    assert(suffix(0x00, 0x00) == "honu_A");
    assert(suffix(0x3F, 0x00) == "piko_A");
    assert(suffix(0xC0, 0x00) == "honu_D");
    assert(suffix(0x41, 0x00) == "nalu_B");
    assert(suffix(0xC5, 0x03) == "makani_P");

    for (int i = 0; i < 64; i++) {
        const char* w = tag_word(i);
        size_t len = strlen(w);
        assert(len > 0 && len <= 6);
        for (size_t k = 0; k < len; k++) assert(w[k] >= 'a' && w[k] <= 'z');
        for (int j = 0; j < i; j++) assert(strcmp(w, tag_word(j)) != 0);
    }

    for (int i = 0; i < 64; i++) {
        for (int letter = 0; letter < 16; letter++) {
            const uint8_t id[6] = {(uint8_t)(i | ((letter & 0x3) << 6)), (uint8_t)(letter >> 2), 0, 0, 0, 0};
            char name[40];
            tag_ble_name("tagvaa", id, name, sizeof name);
            assert(strlen(name) <= 15);
            tag_ble_name("tagvaa log", id, name, sizeof name);
            assert(strlen(name) <= 29);
        }
    }

    const uint8_t id[6] = {0x41, 0x00, 0, 0, 0, 0};
    char name[40];
    tag_ble_name("tagvaa", id, name, sizeof name);
    assert(std::string(name) == "tagvaa nalu_B");

    const uint8_t mac[6] = {0xF1, 0xE2, 0xD3, 0xC4, 0xB5, 0xC5};
    char addr[24];
    tag_addr_string(mac, addr, sizeof addr);
    assert(std::string(addr) == "C5:B5:C4:D3:E2:F1");

    printf("all tag_name tests passed\n");
    return 0;
}
