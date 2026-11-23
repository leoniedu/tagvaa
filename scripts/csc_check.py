"""Scan for "tagvaa", read CSC Feature, print CSC Measurement notifications with computed rpm.

Usage: .venv/bin/python scripts/csc_check.py [notifications=5]
"""
import asyncio
import struct
import sys
import time

from bleak import BleakClient, BleakScanner

CSC_SERVICE = "00001816-0000-1000-8000-00805f9b34fb"
CSC_MEASUREMENT = "00002a5b-0000-1000-8000-00805f9b34fb"
CSC_FEATURE = "00002a5c-0000-1000-8000-00805f9b34fb"


async def main():
    dev, adv = None, None
    found = await BleakScanner.discover(timeout=10, return_adv=True)
    for d, a in found.values():
        name = a.local_name or ""
        if name.startswith("tagvaa ") and not name.startswith("tagvaa log"):
            dev, adv = d, a
    if dev is None:
        print("tagvaa not found")
        return
    print(f"found {adv.local_name} rssi {adv.rssi} dBm, advertised services {adv.service_uuids}")

    prev = None
    count = 0
    done = asyncio.Event()

    def on_measure(_, data: bytearray):
        nonlocal prev, count
        flags, revs, t = struct.unpack("<BHH", data)
        rpm = ""
        if prev:
            drevs = (revs - prev[0]) & 0xFFFF
            dt = ((t - prev[1]) & 0xFFFF) / 1024
            rpm = f"{60 * drevs / dt:.1f} rpm" if dt else ""
        print(f"  {time.strftime('%H:%M:%S')}  {data.hex(' ')}  revs={revs} t={t}  {rpm}", flush=True)
        if not prev or revs != prev[0]:
            prev = (revs, t)
        count += 1
        if count >= limit:
            done.set()

    async with BleakClient(dev) as client:
        feature = await client.read_gatt_char(CSC_FEATURE)
        print(f"CSC Feature: 0x{int.from_bytes(feature, 'little'):04x}")
        await client.start_notify(CSC_MEASUREMENT, on_measure)
        await asyncio.wait_for(done.wait(), timeout=limit + 10)
        await client.stop_notify(CSC_MEASUREMENT)


limit = int(sys.argv[1]) if len(sys.argv) > 1 else 5
asyncio.run(main())
