#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;
use lib qw/lib/;
# use GPSD::Parse;
use Time::HiRes qw//;
use List::MoreUtils qw/natatime/;

#use ZofSensor::HT16K33LED8x8Matrix;

# my $m = ZofSensor::HT16K33LED8x8Matrix->new;

# for my $n (1..100) {
#     for my $x (1..8) {
#         for my $y (1..8) {
#             # $m->clear;
#             # $m->set_one($n % 2, $x, $y);
#             $m->set_col($n % 2, $x);
#             Time::HiRes::sleep(.01);
#         }
#     }
# }

# $m->clear;
# # sleep 2;
# # $m->turn_off;

# __END__
use ZofSensor::PiSugar2Pro;

my $sugar = ZofSensor::PiSugar2Pro->new;
use Acme::Dump::And::Dumper;
warn DnD [ $sugar->read ];


__END__


use Device::SMBus;
use constant BATTERY_VOLTAGE_ADDR => 0x75;

my $dev = Device::SMBus->new(
    I2CBusDevicePath => '/dev/i2c-1',
    I2CDeviceAddress => BATTERY_VOLTAGE_ADDR,
);

while (1) {
    if ($dev->readByteData(0xdc) == 0xff and $dev->readByteData(0xdd) == 0x1f){
        say "Charging";
    }
    else {
        say "NOT charging";
    }
    Time::HiRes::sleep(.5);

    my $vl = $dev->readByteData(0xd0);
    my $vh = $dev->readByteData(0xd1);

    $vh &= 0b0011_1111;
    my $v = ($vh << 8) + $b;
    $v = ($v*0.26855+2600) / 1000;
    # if ($vh & 0x20) {
    #     $vl = ~$vl & 0xff;
    #     $vh = ~$vh & 0x1f;
    #     $v = ((($vh| 0b1100_0000) << 8) + $vl);
    #     $v = (2600.0 - $v * 0.26855) / 1000;
    # }
    # else {
    #     $v = (($vh & 0x1f) << 8 ) + $vl;
    #     $v = (2600 + $v * 0.26855) / 1000;
    # }

    # 3.5624832 => 45%
    # 3.631232  => 64%, 3.7934362 => 76%
    # 3.8025669 => 77%, 3.83022755 => 80%, 3.85385995 => 83%

    my @battery_curve = (
        [4.16, 5.5, 100, 100],
        [4.05, 4.16, 87.5, 100],
        [4.00, 4.05, 75, 87.5],
        [3.92, 4.00, 62.5, 75],
        [3.86, 3.92, 50, 62.5],
        [3.79, 3.86, 37.5, 50],
        [3.66, 3.79, 25, 37.5],
        [3.52, 3.66, 12.5, 25],
        [3.49, 3.52, 6.2, 12.5],
        [3.1, 3.49, 0, 6.2],
        [0, 3.1, 0, 0],
    );

    my $battery_level = 0;
    for my $range (@battery_curve) {
        if ($range->[0] < $v <= $range->[1]) {
            my $level_base = (($v - $range->[0]) / ($range->[1] - $range->[0])) * ($range->[3] - $range->[2]);
            $battery_level = $level_base + $range->[2];
        }
    }

    use Acme::Dump::And::Dumper;
    warn DnD [ ($vh*256+$vl)/16, $v, $battery_level ];
}

__END__

use RPi::DHT; # https://github.com/bublath/rpi-dht
    use RPi::DHT;
    my $pin = 16;
    my $type = 11;
    my $debug = 0;
    my $env = RPi::DHT->new($pin,$type,$debug);
while (1) {
    my ($temp,$humidity) = $env->read;
    use Acme::Dump::And::Dumper;
    warn DnD [ $temp, $humidity ];
}

__END__

use RPi::DHT11;

my $pin = 16;
say "About to start";
my $env = RPi::DHT11->new($pin, 1);
say "Started";
my $temp     = $env->temp;
say "Got temp";
my $humidity = $env->humidity;
say "Read";
use Acme::Dump::And::Dumper;
warn DnD [ { temp => $temp, hum => $humidity } ];

__END__

use Device::SMBus;
use constant BATTERY_VOLTAGE_ADDR => '0x75';

my $dev = Device::SMBus->new(
    I2CBusDevicePath => '/dev/i2c-1',
    I2CDeviceAddress => BATTERY_VOLTAGE_ADDR,
);

use Acme::Dump::And::Dumper;
warn DnD [ $dev->readByteData(0xd0) ];



__END__

my $GPS = GPSD::Parse->new;

while (1) {
    $GPS->poll;
    my $tpv = $GPS->tpv;
    my @sats = values $GPS->satellites->%*;
    my $used = grep $_->{used}, @sats;
    use Acme::Dump::And::Dumper;
    warn DnD [ $tpv, "$used/" . @sats ];
    sleep 2;
}


__END__

use Acme::Dump::And::Dumper;
die DnD [ _get_wifi() ];

sub _get_wifi {
    my $it = natatime 3, split "\n",
        `nmcli -m multiline -f SSID,SECURITY,BARS dev wifi list`;
    my @nets;
    while (my @lines = $it->()) { push @nets, +{ map split(/:\s+/), @lines }}

    my %secs;
    $secs{$_->{SECURITY}}++ for @nets;
    my @secs = map +{
            type  => $_,
            count => $secs{$_}
        }, sort { $secs{$b} <=> $secs{$a} } keys %secs;
    +{
        secs     => \@secs,
        n_open   => scalar(grep $_->{SECURITY} eq '--', @nets),
        all_nets => \@nets,
    }
}



__END__

my $GPS = GPSD::Parse->new;

while (1) {
    $GPS->poll;
    my $tpv = $GPS->tpv;
    use Acme::Dump::And::Dumper;
    warn DnD [ $tpv ];
    sleep 2;
}