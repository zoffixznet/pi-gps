#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;
use GPSD::Parse;
use Time::HiRes qw//;

my $GPS = GPSD::Parse->new;

while (1) {
    $GPS->poll;
    my $tpv = $GPS->tpv;
    use Acme::Dump::And::Dumper;
    warn DnD [ $tpv ];
    sleep 2;
}