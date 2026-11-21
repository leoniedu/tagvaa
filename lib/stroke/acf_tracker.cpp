#include "acf_tracker.h"

#include <math.h>
#include <string.h>

namespace
{
inline int imax(int a, int b) { return a > b ? a : b; }
inline int imin(int a, int b) { return a < b ? a : b; }
} // namespace

AcfTracker::AcfTracker(const AcfParams &p) : P(p)
{
    lam_ = expf(-1.0f / (P.tau * 25.0f));
    esDiv_ = P.esTau * 100.0f;
    lvlDiv_ = P.lvlTau * 100.0f;
    armDecay_ = expf(-0.04f * P.estEvery / P.armTau);
    P.kmin = imax(P.kmin, KLO);
    P.kmax = imin(P.kmax, KHI);
    memset(R_, 0, sizeof R_);
    memset(hist_, 0, sizeof hist_);
}

void AcfTracker::estimate()
{
    arm_ *= armDecay_;
    if (valid_ && P.relStop > 0) {
        lowCount_ = (es_ < P.relStop * P.relStop * lvl_) ? lowCount_ + 1 : 0;
        if (lowCount_ >= P.stopN) { // paddling stopped: forget the old rhythm
            arm_ = lvl_;
            memset(R_, 0, sizeof R_);
            R0_ = 0;
            valid_ = false;
            nraw_ = 0;
            outCount_ = 0;
            lowCount_ = 0;
            return;
        }
    }
    if (R0_ <= 1e-12f || sqrtf(es_) < P.gate) {
        valid_ = false;
        nraw_ = 0;
        outCount_ = 0;
        return;
    }
    float rho[KHI + 2];
    for (int k = P.kmin - 1; k <= P.kmax + 1; k++) rho[k] = R_[k] / R0_;
    auto isMax = [&](int k) { return k >= P.kmin && k <= P.kmax && rho[k] > rho[k - 1] && rho[k] >= rho[k + 1]; };

    int best = -1, bestIn = -1;
    const int kInLo = (int)ceilf(60.0f * 25.0f / P.rmax);
    const int kInHi = (int)floorf(60.0f * 25.0f / (P.rmin > 1.0f ? P.rmin : 1.0f));
    for (int k = P.kmin; k <= P.kmax; k++) {
        if (!isMax(k)) continue;
        if (best < 0 || rho[k] > rho[best]) best = k;
        if (k >= kInLo && k <= kInHi && (bestIn < 0 || rho[k] > rho[bestIn])) bestIn = k;
    }
    // A supported rhythm wins unless an unsupported one is clearly stronger.
    if (best >= 0 && bestIn >= 0 && rho[bestIn] >= P.inFrac * rho[best]) best = bestIn;

    if (best < 0 || rho[best] < P.minRho) {
        weak_ += 0.04f * P.estEvery;
        if (weak_ > P.hold) {
            valid_ = false;
            nraw_ = 0;
            outCount_ = 0;
        }
        return;
    }

    // Octave check: the shortest lag whose correlation is >= oct * best.
    int b = best;
    for (int m = 2; m <= P.octM; m++) {
        float target = (float)best / m;
        if (target < P.kmin - 0.5f) break;
        int kk = -1;
        for (int k = imax((int)floorf(target - 1), P.kmin); k <= imin((int)ceilf(target + 1), P.kmax); k++) {
            if (isMax(k) && (kk < 0 || rho[k] > rho[kk])) kk = k;
        }
        if (kk >= 0 && rho[kk] >= P.oct * rho[best]) b = kk;
    }
    // Slower than supported: prefer a supported fraction of the period.
    if (60.0f * 25.0f / b < P.rmin) {
        for (int m = 2; m <= P.octM; m++) {
            float target = (float)b / m;
            if (target < P.kmin - 0.5f) break;
            float rr = 60.0f * 25.0f / target;
            if (rr < P.rmin || rr > P.rmax) continue;
            int kk = -1;
            for (int k = imax((int)floorf(target - 1), P.kmin); k <= imin((int)ceilf(target + 1), P.kmax); k++) {
                if (isMax(k) && (kk < 0 || rho[k] > rho[kk])) kk = k;
            }
            if (kk >= 0 && rho[kk] >= P.lowOct * rho[b]) {
                b = kk;
                break;
            }
        }
    }

    float den = rho[b - 1] - 2 * rho[b] + rho[b + 1];
    float delta = (den < -1e-12f) ? 0.5f * (rho[b - 1] - rho[b + 1]) / den : 0.0f;
    if (delta > 1.0f) delta = 1.0f;
    if (delta < -1.0f) delta = -1.0f;
    float r = 60.0f * 25.0f / (b + delta);

    // Ambiguous between this rate and a multiple above the supported range: do not trust it.
    for (int m = 2; m <= P.octM; m++) {
        float target = (float)b / m;
        if (target < P.kmin - 0.5f) break;
        if (60.0f * 25.0f / target <= P.rmax) continue;
        for (int k = imax((int)floorf(target - 1), P.kmin); k <= imin((int)ceilf(target + 1), P.kmax); k++) {
            if (isMax(k) && rho[k] >= P.oobOct * rho[b]) r = 2 * P.rmax;
        }
    }

    weak_ = 0;
    raw_[nraw_ % 5] = r;
    nraw_++;
    float med = r;
    if (P.medN > 1 && nraw_ >= P.medN) {
        float v[5];
        for (int j = 0; j < P.medN; j++) v[j] = raw_[(nraw_ - 1 - j) % 5];
        for (int i = 1; i < P.medN; i++) { // insertion sort, medN <= 5
            float key = v[i];
            int j = i - 1;
            while (j >= 0 && v[j] > key) {
                v[j + 1] = v[j];
                j--;
            }
            v[j + 1] = key;
        }
        med = v[P.medN / 2];
    }

    if (med < P.rmin || med > P.rmax) { // a rhythm the display does not support
        if (++outCount_ >= P.outN) valid_ = false;
        return;
    }
    outCount_ = 0;
    if (!valid_) {
        if (es_ < P.relStart * P.relStart * arm_) return; // still the motion left after a stop
        valid_ = true;
        lvl_ = es_;
        lowCount_ = 0;
        rate_ = med;
    } else {
        rate_ += P.alpha * (med - rate_);
    }
}

bool AcfTracker::update(float x, uint32_t samples)
{
    es_ += (x * x - es_) / esDiv_;
    if (valid_) lvl_ += (x * x - lvl_) / lvlDiv_;
    acc_ += x;
    if (++acnt_ < 4) return false;
    float xd = acc_ * 0.25f;
    acc_ = 0;
    acnt_ = 0;

    hist_[nd_ % NH] = xd;
    for (int k = P.kmin - 1; k <= P.kmax + 1; k++) {
        int idx = ((nd_ - k) % NH + NH) % NH;
        R_[k] = lam_ * R_[k] + xd * hist_[idx];
    }
    R0_ = lam_ * R0_ + xd * xd;
    nd_++;
    if (nd_ % P.estEvery == 0) estimate();

    // Strokes: integer crossings of the integrated phase.
    if (!valid_ || rate_ <= 0) {
        wasValid_ = false;
        return false;
    }
    if (!wasValid_) {
        phase_ = 0;
        wasValid_ = true;
    }
    float p0 = phase_;
    phase_ += rate_ / 60.0f * 0.04f;
    if (phase_ >= 1.0f) {
        float f = (1.0f - p0) / (phase_ - p0);
        phase_ -= 1.0f;
        evPos_ = (double)samples - 4.0 + 4.0 * f;
        events_++;
        return true;
    }
    return false;
}
