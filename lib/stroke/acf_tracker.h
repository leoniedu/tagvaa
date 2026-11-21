// Stroke-rate tracker by running autocorrelation ("A" in experiments/rate_lab.cpp).
//
// Input: the band-passed surge signal of StrokeDetector (detector.signal()), one value per
// 100 Hz sample. The signal is averaged to 25 Hz and a recursive autocorrelation
//   R[k] = lambda R[k] + x[n] x[n-k]
// is kept for lags covering ~19..187 strokes/min. Every 0.2 s the period is taken from the
// strongest correlation peak (octave check: the shortest lag with >= oct * best wins),
// refined by a parabola, median + EMA smoothed. Rhythms outside [rmin, rmax] are blanked
// (valid() == false) instead of being mistaken for a multiple or a fraction of the real rate.
// Strokes are the integer crossings of the integrated phase of the rate, so reported stroke
// times are smooth by construction; their count is only meaningful as a cadence, not as a
// total (strokes are missed at the start and extra ones follow a stop).
//
// Plain C++ (no Arduino) so it also builds on the Mac for replay tests. Defaults are the
// values tuned in experiments/tune.R on separate train / validation / fresh data sets.
#pragma once

#include <stdint.h>

struct AcfParams {
    float tau = 3.4f;      // s, forgetting time constant of the autocorrelation
    float alpha = 0.3f;    // EMA weight of each new period estimate
    float minRho = 0.33f;  // weakest correlation peak accepted
    float oct = 0.65f;     // shorter lag (period / 2 .. / octM) wins if its correlation >= oct * best
    float hold = 3.0f;     // s a weak correlation keeps the last rate before the tracker gives up
    float gate = 0.012f;   // g rms of the band-passed surge below which there is no paddling
    float esTau = 1.0f;    // s, time constant of that rms
    int medN = 3;          // median over the last medN period estimates (1, 3 or 5)
    int estEvery = 5;      // new estimate every estEvery 25 Hz steps (5 = 0.2 s)
    int kmin = 8, kmax = 80;        // lags searched at 25 Hz
    int octM = 6;                   // octave check looks at best/2 .. best/octM
    float rmin = 24.0f, rmax = 110.0f; // strokes/min the display supports
    int outN = 2;                   // consecutive out-of-range estimates (0.2 s each) before blanking
    float inFrac = 0.5f;   // a supported rhythm is chosen if its correlation >= inFrac * the strongest anywhere
    float lowOct = 0.5f;   // slower-than-rmin period: a supported fraction of it wins at >= lowOct * its correlation
    float oobOct = 0.75f;  // estimate is unreliable if a fraction above rmax has a peak >= oobOct * the chosen one
    // Stop detection relative to the paddler's own level (hull motion after a stop can stay
    // above `gate` while the decaying memory of the strokes keeps the old rhythm alive).
    float relStop = 0.45f; // stopped when the 1 s rms < relStop * paddling rms (0 = off) ...
    int stopN = 8;         // ... for this many consecutive estimates; the memory is then cleared
    float lvlTau = 8.0f;   // s, paddling rms level, followed while a rhythm is tracked
    float relStart = 0.5f; // after such a stop, a restart needs 1 s rms >= relStart * that level ...
    float armTau = 20.0f;  // s, ... which fades with this time constant
};

class AcfTracker
{
  public:
    explicit AcfTracker(const AcfParams &p = AcfParams());

    // Feed one 100 Hz sample of the band-passed surge. `samples` is the number of samples the
    // detector has consumed including this one. Returns true when a stroke event is emitted;
    // its position (in the same sample units) is eventSample().
    bool update(float x, uint32_t samples);

    bool valid() const { return valid_; }       // a supported rhythm is being tracked
    float rate() const { return rate_; }        // strokes/min, smoothed (meaningful when valid())
    double eventSample() const { return evPos_; }
    uint32_t events() const { return events_; }

  private:
    static constexpr int KLO = 8, KHI = 80, NH = 128;
    void estimate();

    AcfParams P;
    float lam_, esDiv_;
    float R_[KHI + 2], R0_ = 0, hist_[NH];
    int32_t nd_ = 0;
    float acc_ = 0;
    int acnt_ = 0;
    float es_ = 0;
    float raw_[5] = {0, 0, 0, 0, 0};
    int nraw_ = 0, outCount_ = 0;
    float rate_ = 0, weak_ = 0;
    float lvl_ = 0, arm_ = 0, lvlDiv_, armDecay_;
    int lowCount_ = 0;
    bool valid_ = false;
    float phase_ = 0;
    bool wasValid_ = false;
    double evPos_ = 0;
    uint32_t events_ = 0;
};
