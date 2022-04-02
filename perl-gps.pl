#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;
use GPS::NMEA;
use Time::HiRes qw//;

my $gps = GPS::NMEA->new(
    Port => '/dev/serial0',
    Baud => 9600, #19200, #38400, #115200, #9600,
);

while(1) {
    $gps->parse;
    my $data = $gps->{NMEADATA};
    my ($speed, $lon, $lat, $ns, $ew, $course) = @$data{qw/speed_over_ground  lon_ddmm  lat_ddmm  lat_NS  lon_EW  course_made_good/};
    $_ = arcm_to_deg($_) for $lon, $lat, $course;

    if (defined $course) {
        open my $fh, ">", "course" or die $!;
        print $fh $course;
        close $fh;
    }

    # Dump internal NMEA data:
#    $gps->nmea_data_dump;
    use Acme::Dump::And::Dumper;
    say DnD [ map +{ $_ => $data->{$_} }, sort keys %$data ];
}


#while(1) {
#     my ($ns,$lat,$ew,$lon) = $gps->get_position;
#     # decimal portion is arcminutes, so convert to degrees
#     $lat = arcm_to_deg($lat);
#     $lon = arcm_to_deg($lon);
#     $lat *= -1 if $ns eq "S";
#     $lon *= -1 if $ew eq "W";

#     say "[" . sprintf("%.5f", Time::HiRes::time) . "]: ($lat, $lon)";
# }

sub arcm_to_deg {
    my $v = shift;
    return unless defined $v;
    int($v) + ($v - int($v)) * 1.66666667;
}
