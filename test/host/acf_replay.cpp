// Replays a recording through StrokeDetector (front end) + AcfTracker (the on-device pair).
// Input (stdin): lines "seq,t_ms,x_mg,y_mg,z_mg". Output (stdout): "t_s,rate" once a second
// ("NA" when the tracker is blank). Summary on stderr. Optional args key=value override
// AcfParams (e.g. rmin=22 relStop=0); unknown keys are an error.
//
//   c++ -std=c++17 -O2 -I lib/stroke lib/stroke/stroke_detector.cpp lib/stroke/acf_tracker.cpp \
//       test/host/acf_replay.cpp -o .pio/acf_replay
//   .pio/acf_replay < data/session_window.csv > out.csv
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "acf_tracker.h"
#include "stroke_detector.h"

static bool setParam(AcfParams &p, const char *kv)
{
    const char *eq = strchr(kv, '=');
    if (!eq) return false;
    float v = atof(eq + 1);
    size_t n = eq - kv;
#define F(name)                                                  \
    if (n == strlen(#name) && strncmp(kv, #name, n) == 0) {      \
        p.name = (decltype(p.name))v;                            \
        return true;                                             \
    }
    F(tau) F(alpha) F(minRho) F(oct) F(hold) F(gate) F(esTau) F(medN) F(estEvery) F(kmin) F(kmax)
    F(octM) F(rmin) F(rmax) F(outN) F(inFrac) F(lowOct) F(oobOct) F(relStop) F(stopN) F(lvlTau)
    F(relStart) F(armTau)
#undef F
    return false;
}

int main(int argc, char **argv)
{
    AcfParams par;
    for (int i = 1; i < argc; i++) {
        if (!setParam(par, argv[i])) {
            fprintf(stderr, "unknown parameter: %s\n", argv[i]);
            return 2;
        }
    }
    StrokeDetector det;
    AcfTracker acf(par);
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
