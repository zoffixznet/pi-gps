#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;

use lib qw/lib/;
use GPSD::Parse;
use Math::Trig qw/atan/;
use Mojolicious::Lite -signatures;
use List::MoreUtils qw/natatime/;
use Encode qw/decode_utf8/;

my $GPS = GPSD::Parse->new;

get '/' => sub ($c) {
    my $br = $c->param('brightness');
    if ($br and $br =~ /^\d+$/) {
        open my $fh, '>', '/sys/class/backlight/rpi_backlight/brightness'
            or die $!;
        print $fh $br;
        return $c->redirect_to('/');
    }

    $c->render(template => 'index');
};

websocket '/gps' => sub ($c) {
    $c->on(message => sub ($c, $msg) {
        $GPS->poll;
        my $tpv = $GPS->tpv;
        use Acme::Dump::And::Dumper;
        warn DnD [ $tpv ];

          #         {
          #   'altMSL' => '218.9',
          #   'sep' => '84.93',
          #   'climb' => '-0.1',
          #   'alt' => '218.9',
          #   'magtrack' => '292.2145',
          #   'time' => '2022-04-03T01:30:33.000Z',
          #   'eph' => '83.03',
          #   'magvar' => '-10.2',
          #   'epc' => '42.78',
          #   'epy' => '38.854',
          #   'device' => '/dev/serial0',
          #   'eps' => '148.16',
          #   'speed' => '0.514',
          #   'mode' => 3,
          #   'epv' => '21.39',
          #   'ept' => '0.005',
          #   'lat' => '43.683175',
          #   'altHAE' => '183.8',
          #   'lon' => '-79.733746667',
          #   'track' => '302.45',
          #   'class' => 'TPV',
          #   'geoidSep' => '-35.1',
          #   'epx' => '74.082'
          # }

        my $hv = $tpv->{speed}//0;
        my $vv = $tpv->{climb}//0;
        my $deg = 180 / 3.1415926535; # 180/pi = rads to deg
        # round down <10km/h horizontal velocity, to account for noise:
        my $angle = $hv < 10/(18/5) ? 0 : atan($vv/$hv)*$deg;

        $tpv->{$_} //= 0 for qw/speed climb lat lon altMSL mode/;

        my @sats = values %{$GPS->satellites || {}};

        $c->send({json => {
            time    => Time::HiRes::time,
            speed   => sprintf('%.1f', $tpv->{speed}*(18 / 5)), # m/s to km/h
            compass     => $tpv->{track},
            compass_mag => $tpv->{magtrack},
            climb       => sprintf('%.1f', $tpv->{climb}),
            angle       => sprintf('%.3f', $angle),
            lat         => sprintf('%.2f', $tpv->{lat}),
            lon         => sprintf('%.2f', $tpv->{lon}),
            alt         => sprintf('%.2f', $tpv->{altMSL}),
            mode => $tpv->{mode} == 0 ? 'Unknown'
                  : $tpv->{mode} == 1 ? 'No Fix'
                  : $tpv->{mode} == 2 ? '2D'
                  : $tpv->{mode} == 3 ? '3D' : $tpv->{mode},
            sats_used   => scalar(grep   $_->{used}, @sats),
            sats_unused => scalar(grep ! $_->{used}, @sats),

            wifi => _get_wifi(),
        }});
    });
};

app->start;

sub _get_wifi {
    my $it = natatime 3, split "\n",
        decode_utf8 `nmcli -m multiline -f SSID,SECURITY,BARS dev wifi list`;
    my @nets;
    while (my @lines = $it->()) { push @nets, +{ map split(/:\s+/), @lines }}

    my %secs;
    $secs{$_->{SECURITY}//'unknown'}++ for @nets;
    my @secs = map +{
            type  => $_,
            count => $secs{$_}
        }, sort { $secs{$b} <=> $secs{$a} } keys %secs;
    my @open = grep +($_->{SECURITY}//'') eq '--', @nets;
    +{
        secs     => \@secs,
        n_open   => scalar(@open),
        open_nets => \@open,
        all_nets  => \@nets,
        n_all     => scalar(@nets),
    }
}


__DATA__

@@ index.html.ep
<title>ZofTrack</title>
<script>
    var last_stamp = 0;
    function byid(id) { return document.getElementById(id) }
    const ws = new WebSocket('<%= url_for("gps")->to_abs %>');
    ws.onmessage = function (event) {
        var i, l;
        var data = JSON.parse(event.data);

        byid('info-lag').innerHTML
            = 'LAG: ' + ((data.time||0)- last_stamp).toFixed(2) + 's';
        last_stamp = data.time||0;

        byid('needle').style.transform
            = 'rotate(' + data.compass + 'deg)';
        byid('needle-mag').style.transform
            = 'rotate(' + data.compass_mag + 'deg)';
        byid('info-angle-icon').style.transform
            = 'rotate(' + data.angle + 'deg)';

        byid('info-sats').innerHTML = '⬤'.repeat(data.sats_used)
            + '◯'.repeat(data.sats_unused);

        byid('info-speed').innerHTML = '' + data.speed + 'km/h';
        byid('info-climb').innerHTML = '↕' + data.climb + 'm/s';
        byid('info-alt').innerHTML = '↑' + data.alt + 'm';
        byid('info-lat').innerHTML   = 'LAT: '   + data.lat;
        byid('info-lon').innerHTML   = 'LON: '   + data.lon;
        byid('info-angle').innerHTML  = '∠'   + data.angle + '°';
        byid('info-mode').innerHTML  = 'Mode: '   + data.mode;

        byid('wifi-n').innerHTML  = 'Open: '
            + data.wifi.n_open + '/' +  data.wifi.n_all;

        var wifi_open_html = '<table>';
        for (i = 0, l = data.wifi.open_nets.length; i < l; i++) {
            var net = data.wifi.open_nets[i];
            wifi_open_html
                += '<tr><td>' + net.SSID + '</td><td>'
                + net.BARS + '</td><td>' + net.SECURITY + '</td></tr>';
        }
        byid('wifi-open').innerHTML = wifi_open_html + '</table>';

        var wifi_all_html = '<table>';
        for (i = 0, l = data.wifi.all_nets.length; i < l; i++) {
            var net = data.wifi.all_nets[i];
            wifi_all_html
                += '<tr><td>' + net.SSID + '</td><td>'
                + net.BARS + '</td><td>' + net.SECURITY + '</td></tr>';
        }
        byid('wifi-all').innerHTML = wifi_all_html + '</table>';


        byid('debug').innerHTML = event.data;

    };
    ws.onopen = function (event) {
        setInterval(function() { ws.send('poll') }, 1000)
    };
</script>
<!-- meta http-equiv="refresh" content="3" -->
<style>
    html, body {
        margin: 0;
        padding: 0;
    }

    table, td, th, tr {
        border-collapse: collapse;
        border: 1px solid #999;
    }

    #container {
        position: relative;
        padding: 40px;
        margin: 0 auto;
        text-align: center;
        width: 720px;
        height: 399px;
        font-size: 12px;
        background: #fdd;
    }

    #gps {
        width: 400px;
        height: 479px;
        position: absolute;
        left: 0;
        top: 0;
        background: lightblue;
    }
    #brightness {
        width: 399px;
        height: 40px;
        position: absolute;
        left: 400px;
        bottom: 0;
        background: #dfd;
    }
    #brightness a {
        width: 24.5%;
        font-size: 200%;
        color: black;
        text-decoration: none!important;
        border-right: 1px solid #000;
        display: inline-block;
        height: 40px;
        line-height: 40px;
    }
    #brightness a:last-child { border-right: 0 }
    #wifi {
        width: 399px;
        height: 439px;
        position: absolute;
        left: 400px;
        top: 0px;
        background: #fdd;
        text-align: left;
        overflow: auto;
    }
    #wifi table {
        width: 100%;
    }
    #wifi-n {
        font-size: 200%;
    }

    #wifi-open,
    #wifi-all {
        margin-top: 5px;
        font-size: 80%;
    }
    #wifi-open * {
        color: #00c;
    }
    #wifi-open td, #wifi-open th, #wifi-open tr, #wifi-open table {
        border-color: #00c;
    }
    #wifi-all td,
    #wifi-open td {
        border: 0;
    }

    #info-sats,
    #info-speed,
    #info-climb,
    #info-lat,
    #info-lon,
    #info-alt,
    #info-angle,
    #info-lag,
    #info-mode {
        position: absolute;
        font-weight: bold;
        font-size: 150%;
    }
    #info-sats,
    #info-speed {
        left:  0px;
        right: 0px;
        top:   18px;
        text-align: center;
        font-size: 400%
    }
    #info-sats {
        top: 0;
        font-size: 130%;
    }
    #info-climb {
        right: 5px;
        top:   70px;
        font-size: 300%
    }
    #info-alt   {
        left: 5px;
        top:  70px;
        font-size: 300%
    }
    #info-lat   { left:  5px; bottom: 5px }
    #info-lon   { right: 5px; bottom: 5px }
    #info-lag,
    #info-mode,
    #info-angle {
        bottom: 14px;
        left: 0;
        right: 0;
        text-align: center;
        font-size: 80%;
    }
    #info-mode { bottom: 3px; }
    #info-angle {
        font-size: 170%;
        bottom: 110px;
        z-index: 25;
    }

    #debug {
        display: none;
        position: absolute;
        font-size: 100%;
        font-weight: bold;
        text-align: center;
        bottom: 40px;
        left: 0;
        width: 100%;
    }

    #outer {
      position: absolute;
      display: inline-block;
      left: 48.5px;
      height: 300px;
      width: 300px;
      bottom: 40px;
      background: lightblue;
      border-radius: 50%;
      border: 3px solid black;
    }
    #needle {
      height: 100%;
      width: 100%;
      position: absolute;
      top: 0;
      left: 0;
      border-radius: 50%;
      transition: all 1s;
      transform: rotate(0deg);
    }
    #needle:before {
      content: "";
      position: absolute;
      top: 0;
      left: calc(50% - 7.5px);
      height: 50%;
      width: 15px;
      background: black;
    }
    #needle-mag {
      height: 100%;
      width: 100%;
      position: absolute;
      top: 0;
      left: 0;
      border-radius: 50%;
      transition: all 1s;
      transform: rotate(0deg);
    }
    #needle-mag:before {
      content: "";
      position: absolute;
      top: 0;
      left: calc(50% - 7.5px);
      height: 50%;
      width: 2px;
      background: red;
    }

    #angle {
      position: absolute;
      display: inline-block;
      left: 126px;
      height: 150px;
      width: 150px;
      bottom: 116px;
      background: #dfd;
      border-radius: 50%;
      border: 1px solid black;
      z-index: 20;
    }
    #info-angle-icon {
        width: 140px;
        height: 140px;
        position: absolute;
        top: 5px;
        left: 5px;
        background: url(/car.png) center no-repeat;
        background-size: contain;
        transition: all 1s;
        transform: rotate(0deg);
        z-index: 15;
    }

</style>

<div id="container">
    <div id="gps">
        <div id="info-sats"></div>
        <div id="info-speed"></div>
        <div id="info-climb"></div>
        <div id="info-lat"></div>
        <div id="info-lon"></div>
        <div id="info-alt"></div>

        <div id="angle">
            <div id="info-angle"></div>
            <div id="info-angle-icon"></div>
        </div>

        <div id="info-lag"></div>
        <div id="info-mode"></div>

        <div id="outer">
          <div id="needle"></div>
          <div id="needle-mag"></div>
        </div>
    </div>

    <div id="brightness"
      ><a href="?brightness=9"  id="brightness-night">★</a
      ><a href="?brightness=15"  id="brightness-night">☆</a
      ><a href="?brightness=80" id="brightness-cloudy">☁</a
      ><a href="?brightness=255" id="brightness-sunny">☀</a
    ></div>
    <div id="wifi">
        <div id="wifi-n"></div>
        <div id="wifi-open"></div>
        <div id="wifi-all"></div>
    </div>

    <div id="debug"></div>
</div>
