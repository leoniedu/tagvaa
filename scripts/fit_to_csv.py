"""Convert the per-second records of a FIT activity to CSV.

Columns: time (UTC, ISO 8601), cadence, speed (m/s), distance (m), heart_rate,
lat, lon (degrees). Missing values are empty.

Usage: .venv/bin/python scripts/fit_to_csv.py activity.fit [out.csv]
"""
import csv
import sys

import fitdecode

SEMICIRCLE = 180 / 2**31


def main(src, dst):
    rows = 0
    with fitdecode.FitReader(src) as fr, open(dst, "w", newline="") as f:
        out = csv.writer(f)
        out.writerow(["time", "cadence", "speed", "distance", "heart_rate", "lat", "lon"])
        for frame in fr:
            if frame.frame_type != fitdecode.FIT_FRAME_DATA or frame.name != "record":
                continue
            v = {fld.name: fld.value for fld in frame.fields}
            lat, lon = v.get("position_lat"), v.get("position_long")
            out.writerow([
                v["timestamp"].isoformat(),
                v.get("cadence", ""),
                v.get("enhanced_speed", v.get("speed", "")),
                v.get("distance", ""),
                v.get("heart_rate", ""),
                "" if lat is None else round(lat * SEMICIRCLE, 7),
                "" if lon is None else round(lon * SEMICIRCLE, 7),
            ])
            rows += 1
    print(f"{rows} records -> {dst}")


src = sys.argv[1]
main(src, sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".csv")
