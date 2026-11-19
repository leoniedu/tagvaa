// Replays a recording through StrokeDetector (front end) + AcfTracker (the on-device pair).
// Input (stdin): lines "seq,t_ms,x_mg,y_mg,z_mg". Output (stdout): "t_s,rate" once a second
// ("NA" when the tracker is blank). Summary on stderr.
//
//   c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp lib/stroke/acf_tracker.cpp \
//       test/host/acf_replay.cpp -o .pio/acf_replay
//   .pio/acf_replay < data/session_window.csv > out.csv
#include <stdio.h>

#include "acf_tracker.h"
#include "stroke_detector.h"

int main()
{
    StrokeDetector det;
    AcfTracker acf;
    printf("t_s,rate\n");
    char line[256];
    long n = 0;
    while (fgets(line, sizeof line, stdin)) {
        long seq, tms;
        int x, y, z;
        if (sscanf(line, "%ld,%ld,%d,%d,%d", &seq, &tms, &x, &y, &z) != 5) continue;
        det.update(x / 1000.0f, y / 1000.0f, z / 1000.0f);
        if (det.samples() >= 500) acf.update(det.signal(), det.samples());
        n++;
        if (n % 100 == 0) {
            if (acf.valid()) printf("%ld,%.2f\n", n / 100, acf.rate());
            else printf("%ld,NA\n", n / 100);
        }
    }
    fprintf(stderr, "%u events in %.1f min\n", acf.events(), n / 6000.0);
    return 0;
}
