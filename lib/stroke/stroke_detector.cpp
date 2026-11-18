#include "stroke_detector.h"

#include <math.h>

namespace
{
float emaAlpha(float tauS, float fs) { return 1.0f - expf(-1.0f / (tauS * fs)); }

uint32_t median(uint32_t *v, int n)
{
    // insertion sort; n <= 8
    for (int i = 1; i < n; i++) {
        uint32_t key = v[i];
        int j = i - 1;
        while (j >= 0 && v[j] > key) {
            v[j + 1] = v[j];
            j--;
        }
        v[j + 1] = key;
    }
    return (n % 2) ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2;
}
} // namespace

void Biquad::bandpass(float f0, float q, float fs)
{
    float w0 = 2.0f * (float)M_PI * f0 / fs;
    float alpha = sinf(w0) / (2.0f * q);
    float a0 = 1.0f + alpha;
    b0 = alpha / a0;
    b1 = 0.0f;
    b2 = -alpha / a0;
    a1 = -2.0f * cosf(w0) / a0;
    a2 = (1.0f - alpha) / a0;
}

float Biquad::process(float x)
{
    float y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    return y;
}

StrokeDetector::StrokeDetector(const StrokeParams &p) : p_(p)
{
    aGravity_ = emaAlpha(p.gravityTau, p.fs);
    aCov_ = emaAlpha(p.covTau, p.fs);
    aSkew_ = emaAlpha(p.skewTau, p.fs);
    aLevel_ = emaAlpha(p.levelTau, p.fs);
    float f0 = sqrtf(p.bandLo * p.bandHi);
    float q = f0 / (p.bandHi - p.bandLo);
    bp1_.bandpass(f0, q, p.fs);
    bp2_.bandpass(f0, q, p.fs);
}

uint32_t StrokeDetector::minGapSamples() const
{
    uint32_t gap = (uint32_t)(p_.minGapS * p_.fs);
    if (historyLen_ == HISTORY) {
        uint32_t d[HISTORY - 1];
        for (int i = 0; i < HISTORY - 1; i++) {
            d[i] = history_[i + 1] - history_[i];
        }
        uint32_t adaptive = (uint32_t)(p_.minGapFrac * median(d, HISTORY - 1));
        uint32_t cap = (uint32_t)(p_.maxGapS * p_.fs);
        if (adaptive > cap) adaptive = cap;
        if (adaptive > gap) gap = adaptive;
    }
    return gap;
}

void StrokeDetector::confirm()
{
    confirmedIdx_ = pendingIdx_;
    count_++;
    hasPending_ = false;
    if (historyLen_ < HISTORY) {
        history_[historyLen_++] = confirmedIdx_;
    } else {
        for (int i = 0; i < HISTORY - 1; i++) {
            history_[i] = history_[i + 1];
        }
        history_[HISTORY - 1] = confirmedIdx_;
    }
}

bool StrokeDetector::update(float ax, float ay, float az)
{
    const float a[3] = {ax, ay, az};

    // 1. gravity and dynamic part
    if (n_ == 0) {
        for (int i = 0; i < 3; i++) g_[i] = a[i];
    } else {
        for (int i = 0; i < 3; i++) g_[i] += aGravity_ * (a[i] - g_[i]);
    }
    float gNorm = sqrtf(g_[0] * g_[0] + g_[1] * g_[1] + g_[2] * g_[2]);
    if (gNorm < 1e-3f) gNorm = 1e-3f;
    float u[3] = {g_[0] / gNorm, g_[1] / gNorm, g_[2] / gNorm};
    float d[3] = {a[0] - g_[0], a[1] - g_[1], a[2] - g_[2]};

    // 2. horizontal part
    float vert = d[0] * u[0] + d[1] * u[1] + d[2] * u[2];
    float h[3] = {d[0] - vert * u[0], d[1] - vert * u[1], d[2] - vert * u[2]};

    // 3. surge axis: EMA covariance (a plain running mean until the EMA
    //    takes over, so it settles fast) + one power-iteration step
    float ac = 1.0f / (float)(n_ + 1);
    if (ac < aCov_) ac = aCov_;
    c_[0] += ac * (h[0] * h[0] - c_[0]);
    c_[1] += ac * (h[0] * h[1] - c_[1]);
    c_[2] += ac * (h[0] * h[2] - c_[2]);
    c_[3] += ac * (h[1] * h[1] - c_[3]);
    c_[4] += ac * (h[1] * h[2] - c_[4]);
    c_[5] += ac * (h[2] * h[2] - c_[5]);
    float w[3] = {
        c_[0] * v_[0] + c_[1] * v_[1] + c_[2] * v_[2],
        c_[1] * v_[0] + c_[3] * v_[1] + c_[4] * v_[2],
        c_[2] * v_[0] + c_[4] * v_[1] + c_[5] * v_[2],
    };
    float wNorm = sqrtf(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]);
    if (wNorm > 1e-9f) {
        for (int i = 0; i < 3; i++) v_[i] = w[i] / wNorm;
    }
    float surge = h[0] * v_[0] + h[1] * v_[1] + h[2] * v_[2];
    skew_ += aSkew_ * (surge * surge * surge - skew_);

    // 4. band-pass; the sign makes the drive positive (linear, so it can be applied after filtering)
    float bp = bp2_.process(bp1_.process(surge));
    xPrev2_ = xPrev1_;
    xPrev1_ = x_;
    x_ = (skew_ < 0.0f) ? -bp : bp;

    level_ += aLevel_ * (fabsf(x_) - level_);
    thr_ = p_.thresholdK * level_;
    if (thr_ < p_.minAmpG) thr_ = p_.minAmpG;

    n_++;
    if (n_ < (uint32_t)(p_.warmupS * p_.fs)) {
        return false;
    }

    // 5. peaks (the previous sample is a local maximum above threshold)
    bool confirmed = false;
    uint32_t gap = minGapSamples();
    uint32_t idx = n_ - 2; // index of xPrev1_
    if (hasPending_ && idx - pendingIdx_ >= gap) {
        confirm();
        confirmed = true;
    }
    if (xPrev1_ > xPrev2_ && xPrev1_ >= x_ && xPrev1_ > thr_) {
        bool tooClose = false;
        if (hasPending_) {
            tooClose = true; // still within the gap of the pending peak
        } else if (count_ > 0 && idx - confirmedIdx_ < gap) {
            tooClose = true;
        }
        if (!tooClose) {
            hasPending_ = true;
            pendingIdx_ = idx;
            pendingVal_ = xPrev1_;
        } else if (hasPending_ && xPrev1_ > pendingVal_) {
            pendingIdx_ = idx; // a larger peak within the gap replaces the pending one
            pendingVal_ = xPrev1_;
        }
    }
    return confirmed;
}
