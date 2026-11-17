"""Record the Paddle Logger BLE UART stream from the Mac.

Writes the same "Timestamp,Mode,Data" CSV as Bluefruit Connect's UART export
(local time of day per BLE packet), so analysis/read_accel.R handles both.

Usage: .venv/bin/python scripts/ble_log.py out.csv [seconds]
"""
import asyncio
import csv
import sys
import time
from datetime import datetime

from bleak import BleakClient, BleakScanner

NUS_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # notifications from the Tag


async def main(path, seconds):
    dev = await BleakScanner.find_device_by_name("Paddle Logger", timeout=15)
    if dev is None:
        sys.exit("Paddle Logger not found")
    with open(path, "w", newline="") as f:
        out = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        out.writerow(["Timestamp", "Mode", "Data"])

        def on_packet(_, data: bytearray):
            stamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            out.writerow([stamp, "RX", data.decode(errors="replace").rstrip("\n")])

        async with BleakClient(dev) as client:
            print(f"connected, MTU {client.mtu_size}; recording {seconds} s to {path}")
            await client.start_notify(NUS_TX, on_packet)
            start = time.time()
            while time.time() - start < seconds:
                await asyncio.sleep(1)
            await client.stop_notify(NUS_TX)


asyncio.run(main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 60))
