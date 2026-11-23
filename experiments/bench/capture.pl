# Usage: perl experiments/bench/capture.pl /dev/cu.usbmodemXXXX 340 out_serial.txt
# capture.pl PORT SECONDS OUT : serial lines prefixed with host time (ms)
use strict; use Time::HiRes qw(time);
my ($port, $secs, $out) = @ARGV;
system("stty -f $port 115200 raw");
open(my $in, "<", $port) or die "open $port: $!";
open(my $o, ">", $out) or die; select($o); $| = 1;
my $end = time + $secs;
$SIG{ALRM} = sub { exit 0 }; alarm $secs;
while (my $l = <$in>) { printf "%.0f\t%s", time * 1000, $l; last if time > $end; }
