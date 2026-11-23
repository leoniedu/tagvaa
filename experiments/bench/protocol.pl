# Usage: perl experiments/bench/protocol.pl out_events.tsv   (run while capture.pl records)
# protocol.pl EVENTS_OUT : spoken cues + click metronome; logs phase start times (host ms)
use strict; use Time::HiRes qw(time sleep);
my $out = shift; open(my $o, ">", $out) or die; select($o); $| = 1;
my $click = "/System/Library/Sounds/Tink.aiff";
sub say_ { system("say", "-r", "200", $_[0]); }
sub ev { printf "%.0f\t%s\t%s\n", time * 1000, $_[0], $_[1]; }
sub still { my ($name, $msg, $s) = @_; say_($msg); ev($name, 0); sleep $s; }
sub strokes { my ($name, $rate, $s) = @_; say_("$rate per minute, starting now"); ev($name, $rate);
  my $t0 = time; my $k = 0;
  while (time - $t0 < $s) { my $next = $t0 + $k * 60 / $rate; sleep($next - time) if $next > time;
    system("afplay -v 0.6 $click &"); $k++; } }
say_("Bench test starts in 5 seconds. Push the Tag forward on each click, bring it back slowly.");
sleep 5;
still("still0", "Hold still", 10);
strokes("A45", 45, 40);
still("wobbleA", "Stop paddling. Keep wobbling it gently and irregularly", 25);
still("stillA", "Hold still", 10);
strokes("B45", 45, 40);
still("stopB", "Stop. Hold completely still", 20);
strokes("C26", 26, 60);
still("stopC", "Stop. Hold still", 15);
strokes("D32", 32, 45);
still("wobbleD", "Stop paddling. Keep wobbling it gently", 25);
say_("Done. Thank you."); ev("end", 0);
