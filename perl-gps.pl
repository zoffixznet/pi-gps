#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;
use GPSD::Parse;
use Time::HiRes qw//;
use List::MoreUtils qw/natatime/;


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