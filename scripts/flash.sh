#!/bin/sh
# Flash a UF2 onto the Tag over USB, no buttons needed.
# Usage: scripts/flash.sh firmware/m2_accel.uf2
# Works when the Tag runs one of our milestone firmwares (serial "dfu" command)
# or when the RAK4631 bootloader drive is already mounted.
set -e
UF2="$1"
VOL=/Volumes/RAK4631
[ -f "$UF2" ] || { echo "usage: $0 file.uf2"; exit 1; }

if [ ! -f "$VOL/INFO_UF2.TXT" ]; then
    PORT=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
    [ -n "$PORT" ] || { echo "no Tag found on USB"; exit 1; }
    echo "asking $PORT to reboot into the bootloader"
    stty -f "$PORT" 115200
    printf 'dfu\n' > "$PORT" || true
    for i in $(seq 1 20); do [ -f "$VOL/INFO_UF2.TXT" ] && break; sleep 1; done
fi
[ -f "$VOL/INFO_UF2.TXT" ] || { echo "bootloader drive did not appear (Meshtastic running? use: meshtastic --enter-dfu)"; exit 1; }
grep -q "SoftDevice: S140 6.1" "$VOL/INFO_UF2.TXT" || { echo "unexpected SoftDevice, aborting:"; cat "$VOL/INFO_UF2.TXT"; exit 1; }

echo "copying $UF2"
cp -X "$UF2" "$VOL/" 2>/dev/null || true # I/O error at the end is normal: the Tag reboots
for i in $(seq 1 20); do [ ! -d "$VOL" ] && ls /dev/cu.usbmodem* >/dev/null 2>&1 && break; sleep 1; done
echo "done; port: $(ls /dev/cu.usbmodem* 2>/dev/null | head -1)"
