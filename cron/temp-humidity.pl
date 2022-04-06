#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;
use RPi::DHT11;
use Mojo::JSON qw/to_json/;
use Fcntl ':flock';
use Time::HiRes qw//;

use constant DATA_FILE => '/home/zoffix/gps-work/cron/temp-humidity.json';

use RPi::DHT; # https://github.com/bublath/rpi-dht
my $pin = 16;
my $type = 11;
my $debug = 0;
my $env = RPi::DHT->new($pin,$type,$debug);
$| = 1;
while (1) {
    Time::HiRes::sleep(1);
    my ($temp,$humidity) = $env->read;
    next unless defined $temp and defined $humidity;
    my $data = to_json +{
        temp     => $temp,
        humidity => $humidity,
        time     => Time::HiRes::time,
    };

    open my $fh, '>', DATA_FILE or do {
        warn "Could not open data file $!";
        next;
    };

    flock $fh, LOCK_EX or do {
        warn "Could not lock data file - $!";
        next;
    };

    print $fh $data;
    close $fh;
    print '.';
}