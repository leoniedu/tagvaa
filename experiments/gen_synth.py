"""Synthetic hull-surge recordings with known stroke times, for comparing stroke-rate algorithms.

Writes, for each scenario NAME in the output directory:
  NAME.csv          seq,t_ms,x_mg,y_mg,z_mg  (100 Hz, 8 mg steps, Tag rotated arbitrarily)
  NAME_truth.csv    t_s,rate                 (nominal strokes/min, 0 = pause, one row per second)
  NAME_strokes.csv  t_s                      (true stroke starts)

Realism knobs: stroke-to-stroke duration jitter (4 %), amplitude jitter (20 %),
a side-switch spike every 12-18 strokes, sensor noise, optional wave "chop"
(slow sinusoids that overlap the stroke band).

Usage: python3 experiments/gen_synth.py OUTDIR [SEED_OFFSET] [NAME_PREFIX]
"""
import math
import os
import random
import sys

FS = 100


def rot(a, b, c):
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rx = [[1, 0, 0], [0, ca, -sa], [0, sa, ca]]
    ry = [[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]]
    rz = [[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]]
    mm = lambda p, q: [[sum(p[i][k] * q[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(rz, mm(ry, rx))


R = rot(0.4, -0.7, 2.0)


def nominal(segments, t):
    """Nominal rate at time t from segments (kind, ...)."""
    t0 = 0.0
    for seg in segments:
        kind = seg[0]
        dur = seg[-1]
        if t < t0 + dur:
            if kind == "hold":
                return seg[1]
            if kind == "ramp":
                return seg[1] + (seg[2] - seg[1]) * (t - t0) / dur
            return 0.0
        t0 += dur
    return 0.0


def generate(name, outdir, segments, seed, chop=0.0, base_amp=0.10):
    rnd = random.Random(seed)
    total = sum(s[-1] for s in segments)
    n = int(total * FS)
    surge = [0.0] * n
    sway = [0.0] * n
    bob = [0.0] * n
    strokes = []

    t = 0.0
    next_switch = rnd.randint(12, 18)
    side = 1
    k = 0
    while t < total:
        r = nominal(segments, t)
        if r <= 0:
            t += 0.05
            continue
        d = 60.0 / r * (1 + rnd.gauss(0, 0.04))
        d = max(d, 0.3)
        amp = max(0.3 * base_amp, base_amp * (1 + 0.2 * rnd.gauss(0, 1)))
        strokes.append(t)
        k += 1
        switch = k >= next_switch
        if switch:
            k = 0
            next_switch = rnd.randint(12, 18)
            side = -side
        i0, i1 = int(math.ceil(t * FS)), min(n, int(math.ceil((t + d) * FS)))
        for i in range(i0, i1):
            ph = (i / FS - t) / d
            s = amp * (math.sin(2 * math.pi * ph) + 0.35 * math.sin(4 * math.pi * ph + 0.6))
            if switch and ph < 0.08:
                s += 0.25 * math.sin(math.pi * ph / 0.08)
            surge[i] = s
            sway[i] = side * 0.03 * math.sin(2 * math.pi * ph + 0.5)
            bob[i] = 0.04 * math.sin(2 * math.pi * ph + 1)
        t += d

    waves = [(0.35, rnd.uniform(0, 6.28)), (0.62, rnd.uniform(0, 6.28)), (0.45, rnd.uniform(0, 6.28))]
    os.makedirs(outdir, exist_ok=True)
    q = lambda v: max(-4000, min(4000, int(round(v * 1000 / 8) * 8)))
    with open(os.path.join(outdir, name + ".csv"), "w") as f:
        for i in range(n):
            ti = i / FS
            w = sum(math.sin(2 * math.pi * fr * ti + ph) for fr, ph in waves) / len(waves) * chop
            body = (
                surge[i] + 1.0 * w + rnd.gauss(0, 0.008),
                sway[i] + 0.7 * w + rnd.gauss(0, 0.008),
                1 + bob[i] + 1.5 * w + rnd.gauss(0, 0.008),
            )
            tag = [sum(R[r][c] * body[c] for c in range(3)) for r in range(3)]
            f.write(f"{i},{100000 + i * 10},{q(tag[0])},{q(tag[1])},{q(tag[2])}\n")
    with open(os.path.join(outdir, name + "_truth.csv"), "w") as f:
        f.write("t_s,rate\n")
        for s in range(int(total)):
            f.write(f"{s},{nominal(segments, s + 0.5):.2f}\n")
    with open(os.path.join(outdir, name + "_strokes.csv"), "w") as f:
        f.write("t_s\n")
        for s in strokes:
            f.write(f"{s:.3f}\n")
    print(f"{name}: {total:.0f} s, {len(strokes)} strokes")


steps = [("hold", 40, 40), ("hold", 80, 30), ("hold", 45, 30), ("hold", 65, 30), ("hold", 90, 25), ("hold", 40, 25), ("pause", 15)]
ramps = [("ramp", 35, 75, 90), ("pause", 10), ("hold", 50, 40), ("pause", 20), ("ramp", 60, 45, 60)]
out = sys.argv[1]
offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0   # added to every seed: separate train / validation sets
prefix = sys.argv[3] if len(sys.argv) > 3 else ""
generate(prefix + "steps", out, steps, 1 + offset)
generate(prefix + "steps_chop", out, steps, 2 + offset, chop=0.05)
generate(prefix + "ramps", out, ramps, 3 + offset)
generate(prefix + "steady_chop", out, [("hold", 45, 120), ("pause", 15)], 4 + offset, chop=0.09)
generate(prefix + "gentle", out, [("hold", 42, 90), ("pause", 15)], 5 + offset, base_amp=0.035)
