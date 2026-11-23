#include "tag_name.h"

#include <stdio.h>

static const char* const kWords[64] = {
    "honu",   "nalu",  "mano",  "naia",  "hoku",  "makani", "moana",  "kai",
    "kohola", "hee",   "limu",  "ahi",   "aku",   "opah",   "ono",    "mahina",
    "ua",     "ao",    "lani",  "pali",  "iwa",   "manu",   "akule",  "opelu",
    "uhu",    "kala",  "manini", "weke", "papio", "ulua",   "moi",    "mamo",
    "ula",    "kona",  "hau",   "puhi",  "lupe",  "hoe",    "waa",    "ama",
    "iako",   "kia",   "ihu",   "ale",   "opihi", "wana",   "hokuao", "malino",
    "ehu",    "lele",  "holo",  "pae",   "au",    "nenue",  "humu",   "kumu",
    "palani", "maiko", "nohu",  "hapuu", "ulaula", "makau", "ina",    "piko",
};

const char* tag_word(uint8_t index) {
    return kWords[index & 0x3F];
}

void tag_suffix(const uint8_t id[6], char* out, size_t n) {
    uint8_t word = id[0] & 0x3F;
    uint8_t letter = (id[0] >> 6) | ((id[1] & 0x03) << 2);
    snprintf(out, n, "%s_%c", kWords[word], 'A' + letter);
}

void tag_ble_name(const char* prefix, const uint8_t id[6], char* out, size_t n) {
    char suffix[16];
    tag_suffix(id, suffix, sizeof suffix);
    snprintf(out, n, "%s %s", prefix, suffix);
}

void tag_addr_string(const uint8_t mac[6], char* out, size_t n) {
    snprintf(out, n, "%02X:%02X:%02X:%02X:%02X:%02X", mac[5], mac[4], mac[3], mac[2], mac[1], mac[0]);
}
