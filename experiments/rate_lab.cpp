// Offline lab for stroke-rate algorithms that could run on the Tag.
// Nothing here touches the firmware; lib/stroke is used as is.
//
// Input (stdin):  lines "seq,t_ms,x_mg,y_mg,z_mg" (100 Hz)
// Output (stdout): CSV, one row per second:  t_s,B,Bn,Z,A,D,Aint,Dint
//   B    baseline = what runs on the Tag now (StrokeDetector + trimmed-mean
//        timing smoothing from src/m5_stroke/main.cpp), as the head unit shows it
//   Bn   baseline events without the timing smoothing (what the CS300 showed first)
//   Z    hysteresis zero-crossing counter (no gap rules) + the same timing smoothing
//   A    autocorrelation rate tracker; strokes = integrated phase of the rate
//   D    two autocorrelation trackers (fast + slow) blended by their disagreement
//   Aint, Dint  internal rates (strokes/min) before the head-unit model
//   "NA" = the head unit would show nothing (no strokes for 3 s, or first stroke after a pause)
// Summary (stderr): number of strokes each candidate produced.
//
// Build: c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp experiments/rate_lab.cpp -o .pio/rate_lab
// Run:   .pio/rate_lab [tauA=4] [alpha=0.15] [tauFast=2] [tauSlow=6] [esTauS=1] [gateRms=0.012] < data.csv > out.csv
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "stroke_detector.h"

struct Ev {
    double conf; // when the Tag could send it (s)
    double tev;  // stroke time it reports (s)
};

// --- timing smoothing exactly as in src/m5_stroke/main.cpp (N=4) ---
struct Smoother {
    static constexpr int N = 4;
    static constexpr uint32_t PAUSE_MS = 2500;
    static constexpr float PULL = 0.05f;
    static constexpr uint32_t MAX_DRIFT_MS = 5000;
    uint32_t intervals[N] = {0};
    int count = 0;
    uint32_t lastMs = 0, reportedMs = 0;
    uint32_t revs = 0;

    uint32_t smoothedInterval()
    {
        int n = count < N ? count : N;
        uint32_t sum = 0, lo = UINT32_MAX, hi = 0;
        for (int i = 0; i < n; i++) {
            sum += intervals[i];
            lo = std::min(lo, intervals[i]);
            hi = std::max(hi, intervals[i]);
        }
        if (n >= 4) return (sum - lo - hi) / (n - 2);
        return sum / n;
    }
    uint32_t push(uint32_t strokeMs)
    {
        uint32_t interval = strokeMs - lastMs;
        bool first = (revs == 0) || interval >= PAUSE_MS;
        lastMs = strokeMs;
        revs++;
        if (first) {
            count = 0;
            reportedMs = strokeMs;
            return reportedMs;
        }
        intervals[count % N] = interval;
        count++;
        uint32_t predicted = reportedMs + smoothedInterval();
        int32_t error = (int32_t)(strokeMs - predicted);
        reportedMs = predicted + (int32_t)(PULL * error);
        int32_t drift = (int32_t)(reportedMs - strokeMs);
        if (drift > (int32_t)MAX_DRIFT_MS || drift < -(int32_t)MAX_DRIFT_MS) reportedMs = strokeMs;
        return reportedMs;
    }
};

// --- model of the head unit: cadence from (revs, last event time) once a second ---
struct Head {
    int prevRevs = 0;
    double prevT = 0, cad = NAN, lastChange = -1e9;
    bool have = false;
    double tick(double now, int revs, double evT)
    {
        if (revs != prevRevs) {
            if (have && revs > prevRevs && evT > prevT) {
                double dT = evT - prevT;
                cad = (dT > 2.5 * (revs - prevRevs)) ? NAN : 60.0 * (revs - prevRevs) / dT;
            }
            prevRevs = revs;
            prevT = evT;
            have = true;
            lastChange = now;
        }
        if (now - lastChange > 3.0) cad = NAN;
        return cad;
    }
};

// --- Z: one stroke per full cycle of the band-passed surge, by rising zero crossing ---
// A cycle counts only after the signal went below -h (h = 30 % of the running
// amplitude, at least 15 mg), so noise and split peaks do not add strokes.
struct ZeroCross {
    double lvl = 0, xPrev = 0, lastEv = -1e9;
    bool armed = false;
    bool update(double x, double t, double &tev)
    {
        lvl += (fabs(x) - lvl) / 300.0; // ~3 s
        double h = std::max(0.015, 0.3 * 1.57 * lvl);
        bool ev = false;
        if (x < -h) armed = true;
        if (armed && xPrev < 0 && x >= 0 && t - lastEv > 0.4) {
            double frac = -xPrev / (x - xPrev);
            tev = t - 0.01 * (1 - frac);
            lastEv = tev;
            armed = false;
            ev = true;
        }
        xPrev = x;
        return ev;
    }
};

// --- running autocorrelation of the (decimated, 25 Hz) band-passed surge ---
// R[k] = lambda R[k] + x[n] x[n-k] for lags covering 30-110 strokes/min; every
// 0.2 s the strongest peak is the period (shorter lag preferred if its
// correlation is at least 80 % of the best: octave check), refined by parabolic
// interpolation, median-of-3 + EMA smoothed.
struct AcfParams {
    double tau = 3.4;       // s, forgetting time constant of the autocorrelation
    double alpha = 0.3;     // EMA weight of each new period estimate
    double minRho = 0.33;    // weakest correlation peak accepted
    double oct = 0.65;       // shorter lag (period / 2 ... / octM) wins if its correlation >= oct * best
    double hold = 3.0;      // s a weak correlation keeps the last rate before the tracker gives up
    double gate = 0.012;    // g rms of the band-passed surge below which there is no paddling
    double esTau = 1.0;     // s, time constant of that rms
    int medN = 3;           // median over the last medN period estimates (1, 3 or 5)
    int estEvery = 5;       // new estimate every estEvery 25 Hz steps (5 = 0.2 s)
    int kmin = 8, kmax = 80;   // lags searched at 25 Hz = 187 ... 18.75 strokes/min (old range: 13 .. 50)
    int octM = 6;           // octave check looks at best/2 ... best/octM (old: 3)
    double rmin = 30, rmax = 110; // strokes/min the display supports; a rhythm outside is blanked (old: none)
    int outN = 2;           // consecutive out-of-range estimates (0.2 s each) before blanking
    double inFrac = 0.5;    // a supported rhythm (lags for rmin..rmax) is chosen if its correlation is >= inFrac * the
                            // strongest peak anywhere in the searched range; else the rhythm is out of range
    double lowOct = 0.5;    // chosen period slower than rmin: a supported fraction (period / 2 ...) wins if its
                            // correlation >= lowOct * the chosen one (set > 1 to disable)
    double oobOct = 0.75;    // an estimate is unreliable if a fraction (period / 2 ...) with an unsupported rate (> rmax)
                            // has a correlation peak >= oobOct * the chosen one (set > 1 to disable)
};

// --- running autocorrelation of the (decimated, 25 Hz) band-passed surge ---
// R[k] = lambda R[k] + x[n] x[n-k]; every 0.2 s the strongest peak is the period
// (the shortest lag whose correlation is >= oct * best wins: octave check),
// refined by parabolic interpolation, median + EMA smoothed. The lag range is
// wider than the supported rate range so rhythms outside it are recognised
// (and blanked) instead of being mistaken for a multiple or a fraction.
struct AcfCore {
    static constexpr int KLO = 8, KHI = 80, NH = 128;
    double lam;
    double R[KHI + 2], R0 = 0, hist[NH];
    long nd = 0;
    double acc = 0;
    int acnt = 0;
    double es = 0;
    double raw[5] = {0, 0, 0, 0, 0};
    int nraw = 0, outCount = 0;
    double rate = 0, weak = 0;
    bool valid = false;
    AcfParams P;
    double esDiv;

    explicit AcfCore(const AcfParams &p) : lam(exp(-1.0 / (p.tau * 25.0))), P(p), esDiv(p.esTau * 100.0)
    {
        P.kmin = std::max(P.kmin, KLO);
        P.kmax = std::min(P.kmax, KHI);
        memset(R, 0, sizeof R);
        memset(hist, 0, sizeof hist);
    }

    void estimate()
    {
        if (R0 <= 1e-12 || sqrt(es) < P.gate) {
            valid = false;
            nraw = 0;
            outCount = 0;
            return;
        }
        double rho[KHI + 2];
        for (int k = P.kmin - 1; k <= P.kmax + 1; k++) rho[k] = R[k] / R0;
        auto isMax = [&](int k) { return k >= P.kmin && k <= P.kmax && rho[k] > rho[k - 1] && rho[k] >= rho[k + 1]; };
        int best = -1, bestIn = -1;
        const int kInLo = (int)ceil(60.0 * 25.0 / P.rmax), kInHi = (int)floor(60.0 * 25.0 / std::max(P.rmin, 1.0));
        for (int k = P.kmin; k <= P.kmax; k++) {
            if (!isMax(k)) continue;
            if (best < 0 || rho[k] > rho[best]) best = k;
            if (k >= kInLo && k <= kInHi && (bestIn < 0 || rho[k] > rho[bestIn])) bestIn = k;
        }
        if (best >= 0 && bestIn >= 0 && rho[bestIn] >= P.inFrac * rho[best]) best = bestIn;
        if (best < 0 || rho[best] < P.minRho) {
            weak += 0.04 * P.estEvery;
            if (weak > P.hold) {
                valid = false;
                nraw = 0;
                outCount = 0;
            }
            return;
        }
        int b = best;
        for (int m = 2; m <= P.octM; m++) {
            double target = (double)best / m;
            if (target < P.kmin - 0.5) break;
            int kk = -1;
            for (int k = std::max((int)floor(target - 1), P.kmin); k <= std::min((int)ceil(target + 1), P.kmax); k++) {
                if (isMax(k) && (kk < 0 || rho[k] > rho[kk])) kk = k;
            }
            if (kk >= 0 && rho[kk] >= P.oct * rho[best]) b = kk;
        }
        if (60.0 * 25.0 / b < P.rmin) { // slower than supported: prefer a supported fraction of it
            for (int m = 2; m <= P.octM; m++) {
                double target = (double)b / m;
                if (target < P.kmin - 0.5) break;
                double rr = 60.0 * 25.0 / target;
                if (rr < P.rmin || rr > P.rmax) continue;
                int kk = -1;
                for (int k = std::max((int)floor(target - 1), P.kmin); k <= std::min((int)ceil(target + 1), P.kmax); k++) {
                    if (isMax(k) && (kk < 0 || rho[k] > rho[kk])) kk = k;
                }
                if (kk >= 0 && rho[kk] >= P.lowOct * rho[b]) {
                    b = kk;
                    break;
                }
            }
        }
        double den = rho[b - 1] - 2 * rho[b] + rho[b + 1];
        double delta = (den < -1e-12) ? 0.5 * (rho[b - 1] - rho[b + 1]) / den : 0.0;
        double lag = b + std::max(-1.0, std::min(1.0, delta));
        double r = 60.0 * 25.0 / lag;
        // Ambiguous between this rate and a multiple above the supported range: do not trust it.
        for (int m = 2; m <= P.octM; m++) {
            double target = (double)b / m;
            if (target < P.kmin - 0.5) break;
            if (60.0 * 25.0 / target <= P.rmax) continue;
            for (int k = std::max((int)floor(target - 1), P.kmin); k <= std::min((int)ceil(target + 1), P.kmax); k++) {
                if (isMax(k) && rho[k] >= P.oobOct * rho[b]) r = 2 * P.rmax;
            }
        }
        weak = 0;
        raw[nraw % 5] = r;
        nraw++;
        double med = r;
        if (P.medN > 1 && nraw >= P.medN) {
            double v[5];
            for (int j = 0; j < P.medN; j++) v[j] = raw[(nraw - 1 - j) % 5];
            std::sort(v, v + P.medN);
            med = v[P.medN / 2];
        }
        if (med < P.rmin || med > P.rmax) { // a rhythm the display does not support
            if (++outCount >= P.outN) valid = false;
            return;
        }
        outCount = 0;
        if (!valid) {
            valid = true;
            rate = med;
        } else {
            rate += P.alpha * (med - rate);
        }
    }

    // Feed one 100 Hz sample; returns true on every 4th (a 25 Hz step happened).
    bool update(double x)
    {
        es += (x * x - es) / esDiv; // short-term energy for the stop gate
        acc += x;
        if (++acnt < 4) return false;
        double xd = acc / 4;
        acc = 0;
        acnt = 0;
        hist[nd % NH] = xd;
        for (int k = P.kmin - 1; k <= P.kmax + 1; k++) {
            long idx = ((nd - k) % NH + NH) % NH;
            R[k] = lam * R[k] + xd * hist[idx];
        }
        R0 = lam * R0 + xd * xd;
        nd++;
        if (nd % P.estEvery == 0) estimate();
        return true;
    }
};

// Strokes = integer crossings of the integrated phase of a rate; reported times are smooth by construction.
struct Phase {
    double phase = 0;
    bool wasValid = false;
    void step(double t, bool valid, double rate, std::vector<Ev> &out)
    {
        if (!valid || rate <= 0) {
            wasValid = false;
            return;
        }
        if (!wasValid) {
            phase = 0;
            wasValid = true;
        }
        double p0 = phase;
        phase += rate / 60.0 * 0.04;
        if (floor(phase) > floor(p0)) {
            double f = (floor(phase) - p0) / (phase - p0);
            out.push_back({t, t - 0.04 + f * 0.04});
        }
    }
};

static double cadenceAt(const std::vector<Ev> &ev, size_t &p, Head &h, double tick, int &revs, double &lastT)
{
    while (p < ev.size() && ev[p].conf <= tick) {
        revs++;
        lastT = ev[p].tev;
        p++;
    }
    return h.tick(tick, revs, lastT);
}

int main(int argc, char **argv)
{
    // Parameters: key=value (e.g. tau=2.5 minRho=0.3 fast=1), or the old positional
    // tau alpha tauFast tauSlow esTau gate.
    std::map<std::string, double> kv;
    const char *pos[] = {"tau", "alpha", "tauFast", "tauSlow", "esTau", "gate"};
    int np = 0;
    for (int i = 1; i < argc; i++) {
        const char *eq = strchr(argv[i], '=');
        if (eq) kv[std::string(argv[i], eq - argv[i])] = atof(eq + 1);
        else if (np < 6) kv[pos[np++]] = atof(argv[i]);
    }
    auto get = [&](const char *k, double d) { return kv.count(k) ? kv[k] : d; };
    AcfParams pa;
    pa.tau = get("tau", pa.tau);
    pa.alpha = get("alpha", pa.alpha);
    pa.minRho = get("minRho", pa.minRho);
    pa.oct = get("oct", pa.oct);
    pa.hold = get("hold", pa.hold);
    pa.gate = get("gate", pa.gate);
    pa.esTau = get("esTau", pa.esTau);
    pa.medN = (int)get("medN", pa.medN);
    pa.estEvery = (int)get("estEvery", pa.estEvery);
    pa.kmin = (int)get("kmin", pa.kmin);
    pa.kmax = (int)get("kmax", pa.kmax);
    pa.octM = (int)get("octM", pa.octM);
    pa.rmin = get("rmin", pa.rmin);
    pa.rmax = get("rmax", pa.rmax);
    pa.outN = (int)get("outN", pa.outN);
    pa.oobOct = get("oobOct", pa.oobOct);
    pa.lowOct = get("lowOct", pa.lowOct);
    pa.inFrac = get("inFrac", pa.inFrac);
    bool fast = get("fast", 0) > 0; // only A: output t_s,A,Aint
    AcfParams pf = pa, ps = pa;
    pf.tau = get("tauFast", 2.0);
    pf.alpha = 0.3;
    ps.tau = get("tauSlow", 6.0);
    StrokeDetector det;
    Smoother smB, smZ;
    ZeroCross zc;
    AcfCore acfA(pa), acfF(pf), acfS(ps);
    Phase phA, phD;
    std::vector<Ev> evB, evBn, evZ, evA, evD;
    Head hB, hBn, hZ, hA, hD;
    size_t pB = 0, pBn = 0, pZ = 0, pA = 0, pD = 0;
    int rB = 0, rBn = 0, rZ = 0, rA = 0, rD = 0;
    double lB = 0, lBn = 0, lZ = 0, lA = 0, lD = 0;
    double dRate = 0;
    bool dValid = false;

    printf(fast ? "t_s,A,Aint\n" : "t_s,B,Bn,Z,A,D,Aint,Dint\n");
    auto fmt = [](double v) {
        static char buf[4][32];
        static int i = 0;
        i = (i + 1) % 4;
        if (std::isnan(v)) snprintf(buf[i], 32, "NA");
        else snprintf(buf[i], 32, "%.2f", v);
        return buf[i];
    };

    char line[256];
    long n = 0;
    while (fgets(line, sizeof line, stdin)) {
        long seq, tms;
        int x, y, z;
        if (sscanf(line, "%ld,%ld,%d,%d,%d", &seq, &tms, &x, &y, &z) != 5) continue;
        double t = (n + 1) / 100.0;
        bool stroke = det.update(x / 1000.0f, y / 1000.0f, z / 1000.0f);
        if (stroke && !fast) {
            double tev = det.strokeSample() / 100.0;
            evBn.push_back({t, tev});
            uint32_t rep = smB.push((uint32_t)llround(tev * 1000));
            evB.push_back({t, rep / 1000.0});
        }
        double xs = det.signal();
        if (n >= 500) {
            double tev;
            if (!fast && zc.update(xs, t, tev)) {
                evZ.push_back({t, smZ.push((uint32_t)llround(tev * 1000)) / 1000.0});
            }
            if (acfA.update(xs)) phA.step(t, acfA.valid, acfA.rate, evA);
            bool stepped = false;
            if (!fast) {
                stepped = acfF.update(xs);
                acfS.update(xs);
            }
            if (stepped) {
                // D: slow tracker normally; blend toward the fast one as they disagree (6 % -> 16 %)
                dValid = acfS.valid || acfF.valid;
                if (acfS.valid && acfF.valid) {
                    double dev = fabs(acfF.rate - acfS.rate) / acfS.rate;
                    double g = std::max(0.0, std::min(1.0, (dev - 0.06) / 0.10));
                    dRate = acfS.rate + g * (acfF.rate - acfS.rate);
                } else {
                    dRate = acfS.valid ? acfS.rate : acfF.rate;
                }
                phD.step(t, dValid, dRate, evD);
            }
        }
        n++;
        if (n % 100 == 0) {
            double tick = n / 100.0;
            if (fast) {
                printf("%.0f,%s", tick, fmt(cadenceAt(evA, pA, hA, tick, rA, lA)));
                printf(",%s\n", acfA.valid ? fmt(acfA.rate) : "NA");
            } else {
                printf("%.0f,%s", tick, fmt(cadenceAt(evB, pB, hB, tick, rB, lB)));
                printf(",%s", fmt(cadenceAt(evBn, pBn, hBn, tick, rBn, lBn)));
                printf(",%s", fmt(cadenceAt(evZ, pZ, hZ, tick, rZ, lZ)));
                printf(",%s", fmt(cadenceAt(evA, pA, hA, tick, rA, lA)));
                printf(",%s", fmt(cadenceAt(evD, pD, hD, tick, rD, lD)));
                printf(",%s", acfA.valid ? fmt(acfA.rate) : "NA");
                printf(",%s\n", dValid ? fmt(dRate) : "NA");
            }
        }
    }
    fprintf(stderr, "strokes: B %zu, Bn %zu, Z %zu, A %zu, D %zu (%.1f min)\n", evB.size(), evBn.size(), evZ.size(),
            evA.size(), evD.size(), n / 6000.0);
    return 0;
}
