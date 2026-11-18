// Replays a recording through the on-device stroke detector on the Mac.
// Input (stdin): lines "seq,t_ms,x_mg,y_mg,z_mg" (other lines are ignored).
// Output (stdout): "stroke,seq,t_ms" per confirmed stroke, then a summary.
//
// Build and run:
//   c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp \
//       test/host/stroke_replay.cpp -o .pio/stroke_replay
//   .pio/stroke_replay < data/session_clean.csv
#include <stdio.h>

#include <vector>

#include "stroke_detector.h"

int main()
{
    StrokeDetector det;
    std::vector<long> seqs, tms;
    char line[256];
    long first_seq = -1, last_seq = 0;
    while (fgets(line, sizeof line, stdin)) {
        long seq, t;
        int x, y, z;
        if (sscanf(line, "%ld,%ld,%d,%d,%d", &seq, &t, &x, &y, &z) != 5) {
            continue;
        }
        if (first_seq < 0) first_seq = seq;
        last_seq = seq;
        seqs.push_back(seq);
        tms.push_back(t);
        if (det.update(x / 1000.0f, y / 1000.0f, z / 1000.0f)) {
            uint32_t i = det.strokeSample();
            printf("stroke,%ld,%ld\n", seqs[i], tms[i]);
        }
    }
    const float *v = det.surgeAxis();
    double minutes = (last_seq - first_seq) / 100.0 / 60.0;
    fprintf(stderr, "%u samples, %u strokes, %.1f min, %.1f strokes/min; surge axis %.2f %.2f %.2f\n", det.samples(),
            det.strokes(), minutes, det.strokes() / minutes, v[0], v[1], v[2]);
    return 0;
}
