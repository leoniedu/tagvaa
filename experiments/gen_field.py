"""Synthetic recordings of conditions seen on the water on 2026-11-21 (OC1, CS300 + watch):
stops with hull motion that does not die out, swell at a stroke-like rhythm, slow paddling
near 30/min, a sudden sprint, and a paddler who eases off.

The "sea" is band-passed noise (0.5-2 Hz, the tracker's band) present the whole time;
its rms is what the Tag still measures after a stop (0.015-0.04 g on the water, vs
0.05-0.10 g while paddling). Strokes are shaped as in gen_synth.py.

Writes, for each scenario NAME in OUTDIR:
  NAME.csv        seq,t_ms,x_mg,y_mg,z_mg  (100 Hz, 8 mg steps, Tag rotated)
  NAME_truth.csv  t_s,rate,amp             (nominal strokes/min, 0 = not paddling; stroke amplitude, g)

Usage: python3 experiments/gen_field.py OUTDIR [SEEDS]
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


class Bandpass:
    """RBJ band-pass biquad (constant 0 dB peak gain)."""

    def __init__(self, f0, q):
        w = 2 * math.pi * f0 / FS
        al = math.sin(w) / (2 * q)
        a0 = 1 + al
        self.b = (al / a0, 0.0, -al / a0)
        self.a = (-2 * math.cos(w) / a0, (1 - al) / a0)
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def __call__(self, x):
        y = self.b[0] * x + self.b[2] * self.x2 - self.a[0] * self.y1 - self.a[1] * self.y2
        self.x2, self.x1, self.y2, self.y1 = self.x1, x, self.y1, y
        return y


def sea_noise(n, rms, rnd):
    """Band-limited noise (0.5-2 Hz) scaled to `rms` g."""
    f1, f2 = Bandpass(1.0, 0.7), Bandpass(1.0, 0.7)
    v = [f2(f1(rnd.gauss(0, 1))) for _ in range(n + 500)][500:]
    s = math.sqrt(sum(x * x for x in v) / n)
    return [x * rms / s for x in v]


def segment_at(segs, t):
    t0 = 0.0
    for r0, r1, dur, amp in segs:
        if t < t0 + dur:
            return r0 + (r1 - r0) * (t - t0) / dur, amp
        t0 += dur
    return 0.0, 0.0


def generate(name, outdir, segs, seed, sea=0.02, swell=None):
    """segs: list of (rate_start, rate_end, seconds, stroke_amplitude_g); rate 0 = not paddling.
    swell: optional (strokes/min equivalent, amplitude g) sinusoid along the surge axis."""
    rnd = random.Random(seed)
    total = sum(s[2] for s in segs)
    n = int(total * FS)
    surge, sway, bob = [0.0] * n, [0.0] * n, [0.0] * n
    t, k, side = 0.0, 0, 1
    next_switch = rnd.randint(12, 18)
    while t < total:
        r, amp = segment_at(segs, t)
        if r <= 0:
            t += 0.05
            continue
        d = max(0.3, 60.0 / r * (1 + rnd.gauss(0, 0.04)))
        a = max(0.3 * amp, amp * (1 + 0.2 * rnd.gauss(0, 1)))
        k += 1
        switch = k >= next_switch
        if switch:
            k, next_switch, side = 0, rnd.randint(12, 18), -side
        for i in range(int(math.ceil(t * FS)), min(n, int(math.ceil((t + d) * FS)))):
            ph = (i / FS - t) / d
            s = a * (math.sin(2 * math.pi * ph) + 0.35 * math.sin(4 * math.pi * ph + 0.6))
            if switch and ph < 0.08:
                s += 2.5 * amp * math.sin(math.pi * ph / 0.08)
            surge[i] = s
            sway[i] = side * 0.3 * amp * math.sin(2 * math.pi * ph + 0.5)
            bob[i] = 0.4 * amp * math.sin(2 * math.pi * ph + 1)
        t += d
    sx, sy, sz = (sea_noise(n, sea * f, rnd) for f in (1.0, 0.7, 1.0))
    sw_ph = rnd.uniform(0, 6.28)
    q = lambda v: max(-4000, min(4000, int(round(v * 1000 / 8) * 8)))
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, name + ".csv"), "w") as f:
        for i in range(n):
            w = swell[1] * math.sin(2 * math.pi * swell[0] / 60 * i / FS + sw_ph) if swell else 0.0
            body = (surge[i] + sx[i] + w + rnd.gauss(0, 0.008),
                    sway[i] + sy[i] + 0.5 * w + rnd.gauss(0, 0.008),
                    1 + bob[i] + sz[i] + 0.8 * w + rnd.gauss(0, 0.008))
            tag = [sum(R[r][c] * body[c] for c in range(3)) for r in range(3)]
            f.write(f"{i},{100000 + i * 10},{q(tag[0])},{q(tag[1])},{q(tag[2])}\n")
    with open(os.path.join(outdir, name + "_truth.csv"), "w") as f:
        f.write("t_s,rate,amp\n")
        for s in range(int(total)):
            r, amp = segment_at(segs, s + 0.5)
            f.write(f"{s},{r:.2f},{amp:.3f}\n")
    print(f"{name}: {total:.0f} s")


def stops(rates, paddle=50, rest=30, amp=0.10):
    segs = [(0, 0, 10, 0)]
    for r in rates:
        segs += [(r, r, paddle, amp), (0, 0, rest, 0)]
    return segs


if __name__ == "__main__":
    out = sys.argv[1]
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    for s in range(seeds):
        b = 1000 * (s + 1)
        rr = random.Random(b).sample([40, 45, 48, 50, 55], 4)
        for sea in (10, 20, 30, 40, 55):  # mg rms of the sea
            generate(f"s{s}_stops_sea{sea}", out, stops(rr), b + sea, sea=sea / 1000)
        # swell at 45/min while resting: a wave rhythm the tracker cannot tell from paddling
        generate(f"s{s}_stops_swell", out, stops(rr), b + 1, sea=0.015, swell=(45, 0.025))
        # slow paddling around the old 30/min floor
        generate(f"s{s}_slow", out, [(0, 0, 10, 0)] + [(r, r, 60, 0.10) for r in (34, 31, 28, 25, 22, 20)] + [(0, 0, 20, 0)], b + 2)
        # 08:41-like: steady 38, sprint 55, settle at 33
        generate(f"s{s}_sprint", out, [(0, 0, 10, 0), (38, 38, 60, 0.08), (55, 55, 25, 0.12), (33, 33, 90, 0.08), (0, 0, 20, 0)], b + 3)
        # easing off without stopping: stroke amplitude 0.10 -> 0.05 -> 0.035 g, then back
        generate(f"s{s}_soften", out, [(0, 0, 10, 0), (46, 46, 60, 0.10), (44, 44, 60, 0.05), (42, 42, 60, 0.035), (46, 46, 60, 0.10), (0, 0, 20, 0)], b + 4, sea=0.015)
        # steady rates with chop, for half-rate errors once the floor is lower
        for r in (40, 50, 60):
            generate(f"s{s}_steady{r}", out, [(0, 0, 10, 0), (r, r, 150, 0.08), (0, 0, 20, 0)], b + 10 + r, sea=0.03)
