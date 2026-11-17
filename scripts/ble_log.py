"""Record the OC6 Logger BLE UART stream to a CSV file.

Usage: .venv/bin/python scripts/ble_log.py out.csv [seconds]
"""
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

NUS_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # notifications from the Tag


async def main(path, seconds):
    dev = await BleakScanner.find_device_by_name("OC6 Logger", timeout=15)
    if dev is None:
        sys.exit("OC6 Logger not found")
    with open(path, "wb") as f:
        async with BleakClient(dev) as client:
            print(f"connected, MTU {client.mtu_size}; recording {seconds} s to {path}")
            await client.start_notify(NUS_TX, lambda _, data: f.write(data))
            start = time.time()
            while time.time() - start < seconds:
                await asyncio.sleep(1)
            await client.stop_notify(NUS_TX)


asyncio.run(main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 60))
