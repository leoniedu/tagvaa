// Paddle stroke detector: one call per accelerometer sample (in g).
// Port of analysis/stroke_rate.R (stroke_signal + detect_strokes), causal:
//   1. gravity = EMA low-pass per axis; dynamic = raw - gravity
//   2. horizontal = dynamic minus its component along gravity
//   3. surge axis = principal direction of the horizontal part, tracked with
//      an EMA covariance and one power-iteration step per sample (R uses a
//      PCA over the whole session); sign chosen so the drive is positive
//   4. band-pass 0.5-2 Hz (two RBJ biquads)
//   5. peaks above max(min_amp, k * running mean |signal|); a peak is
//      confirmed once no larger one can replace it within the minimum gap,
//      which adapts to the recent stroke interval
// Plain C++ (no Arduino), so it also builds on the Mac for replay tests.
#pragma once

#include <stdint.h>

struct StrokeParams {
    float fs = 100.0f;          // sample rate, Hz
    float gravityTau = 2.0f;    // s
    float covTau = 20.0f;       // s, surge-axis covariance
    float skewTau = 30.0f;      // s, sign of the surge axis
    float bandLo = 0.5f;        // Hz
    float bandHi = 2.0f;        // Hz
    float levelTau = 3.0f;      // s, running mean |signal|
    float thresholdK = 0.5f;    // peak > k * level ...
    float minAmpG = 0.02f;      // ... and > this
    float minGapS = 0.6f;       // strokes at least this far apart ...
    float minGapFrac = 0.6f;    // ... and this fraction of the recent median interval,
    float maxGapS = 1.0f;       // ... capped here (else missed strokes inflate the gap and lock in)
    float warmupS = 5.0f;       // no strokes before the filters settle
};

class Biquad
{
  public:
    void bandpass(float f0, float q, float fs);
    float process(float x);

  private:
    float b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    float x1 = 0, x2 = 0, y1 = 0, y2 = 0;
};

class StrokeDetector
{
  public:
    explicit StrokeDetector(const StrokeParams &p = StrokeParams());

    // Feed one sample (g). Returns true when a stroke is confirmed; its peak
    // sample index is then strokeSample(). Confirmation lags the peak by
    // about one minimum gap (~0.6-0.9 s).
    bool update(float ax, float ay, float az);

    uint32_t samples() const { return n_; }
    uint32_t strokes() const { return count_; }
    uint32_t strokeSample() const { return confirmedIdx_; }
    float signal() const { return x_; }       // band-passed surge, g
    float threshold() const { return thr_; }  // current peak threshold, g
    const float *surgeAxis() const { return v_; }

  private:
    static constexpr int HISTORY = 9; // confirmed stroke indices kept (8 intervals)
    uint32_t minGapSamples() const;
    void confirm();

    StrokeParams p_;
    float aGravity_, aCov_, aSkew_, aLevel_;
    Biquad bp1_, bp2_;

    uint32_t n_ = 0;
    float g_[3] = {0, 0, 0};
    float c_[6] = {0, 0, 0, 0, 0, 0}; // covariance xx, xy, xz, yy, yz, zz
    float v_[3] = {1, 0, 0};
    float skew_ = 0;
    float level_ = 0;
    float x_ = 0, xPrev1_ = 0, xPrev2_ = 0, thr_ = 0;

    bool hasPending_ = false;
    uint32_t pendingIdx_ = 0;
    float pendingVal_ = 0;
    uint32_t confirmedIdx_ = 0;
    uint32_t count_ = 0;
    uint32_t history_[HISTORY] = {0};
    int historyLen_ = 0;
};
