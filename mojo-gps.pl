#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;

use lib qw/lib/;
use GPSD::Parse;
use Math::Trig qw/atan/;
use Mojolicious::Lite -signatures;
use List::MoreUtils qw/natatime/;
use Time::HiRes qw//;
use Encode qw/decode_utf8/;

use constant DHT11_DATA_FILE =>'/home/zoffix/gps-work/cron/temp-humidity.json';

use ZofSensor::Accel;
use ZofSensor::PiSugar2Pro;
use ZofSensor::HT16K33LED8x8Matrix;
use ZofSensor::ActiveBuzzer;
use ZofSensor::LightSensor;
use ZofSensor::UV;
use ZofSensor::DHT11;

my $GPS = GPSD::Parse->new;
my $HID_KBD_AFTER_START = 0;
my $HIDE_KBD_AFTER = time + 10;
my $IS_CAR_STOPPED    = 0;
my $CAR_STOPPED_SINCE = 0;
my $CALLIBRATE_ACCEL_NEXT_STOP = 1;
my $kmh = 3.6; # m per s to km per h convertion ratio

my $ACCEL  = ZofSensor::Accel->new(axis => { y => 'z', z => 'y'});
my $SUGAR  = ZofSensor::PiSugar2Pro->new;
my $MATRIX = ZofSensor::HT16K33LED8x8Matrix->new;
my $BUZZER = ZofSensor::ActiveBuzzer->new;
my $LIGHT  = ZofSensor::LightSensor->new;
my $UV     = ZofSensor::UV->new;
my $DHT11  = ZofSensor::DHT11->new(cron_data_file => DHT11_DATA_FILE);

get '/' => sub ($c) {
    $ACCEL->save_correction;
    my $br = $c->param('brightness');
    if ($br and $br =~ /^\d+$/) {
        open my $fh, '>', '/sys/class/backlight/rpi_backlight/brightness'
            or die $!;
        print $fh $br;
        return $c->redirect_to('/');
    }

    if ($c->param('show_kbd')) {
        show_keyboard();
        return $c->redirect_to('/');
    }
    if ($c->param('hide_kbd')) {
        hide_keyboard();
        return $c->redirect_to('/');
    }

    if ($c->param('shutdown')) {
        local $ENV{DISPLAY} = ':0.0';
        system qw/wmctrl -c Firefox/ for 1..3;
        sleep 1;
        system qw/shutdown -h now/;
        return $c->redirect_to('/');
    }

    if ($c->param('reboot')) {
        local $ENV{DISPLAY} = ':0.0';
        system qw/wmctrl -c Firefox/ for 1..3;
        sleep 1;
        system qw/reboot/;
        return $c->redirect_to('/');
    }


    $c->render(template => 'index');
};

websocket '/gps' => sub ($c) {
    $c->on(message => sub ($c, $msg) {
        {
            # Use of uninitialized value $lat in pattern match (m//) at /usr/local/share/perl/5.34.0/GPSD/Parse.pm line 186, <GEN1> chunk 132
            local $SIG{__WARN__} = sub {};
            $GPS->poll;
        }
        if (not $HID_KBD_AFTER_START and time > $HIDE_KBD_AFTER) {
            # We do this timed stuff, because `onboard` starts a bit late
            # so hiding it from shell start script doesn't quite work
            $HID_KBD_AFTER_START = 1;
            hide_keyboard();
        }
        my $tpv = $GPS->tpv;
        # use Acme::Dump::And::Dumper;
        # warn DnD [ $tpv ];

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

        $tpv->{$_} //= 0 for qw/speed climb lat lon altMSL mode/;

        my $hv = $tpv->{speed}//0;
        my $vv = $tpv->{climb}//0;
        my $deg = 180 / 3.1415926535; # 180/pi = rads to deg
        # round down <10km/h horizontal velocity, to account for noise:
        my $angle = $hv*$kmh < 10 ? 0 : atan($vv/$hv)*$deg;

        # consider car stopped if we got a GPS fix
        # and are below 3km/h to account for noise
        if (($tpv->{mode}||0) > 1 and $hv*$kmh < 3) {
            $CAR_STOPPED_SINCE = Time::HiRes::time unless $IS_CAR_STOPPED;
            $IS_CAR_STOPPED    = 1;
        }
        else {
            $IS_CAR_STOPPED = 0;
            $CALLIBRATE_ACCEL_NEXT_STOP = 1;
        }

        # re-callibrate accelerometer offset, if we're stopped for a while
        if ($IS_CAR_STOPPED and $CALLIBRATE_ACCEL_NEXT_STOP
            and Time::HiRes::time() - $CAR_STOPPED_SINCE > 5
        ) {
            $ACCEL->save_correction;
            $CALLIBRATE_ACCEL_NEXT_STOP = 0;
        }

        my $accel_data = $ACCEL->read;
        $accel_data->{y} > .5 ? $BUZZER->buzz_on : $BUZZER->buzz_off;

        my @sats = values %{$GPS->satellites || {}};

        $c->send({json => {
            time    => Time::HiRes::time,
            speed   => sprintf('%.1f', $tpv->{speed}*$kmh), # m/s to km/h
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
            accel => $accel_data,
            sugar => $SUGAR->read,
            light => $LIGHT->read,
            uv    => $UV->read,
            dht11 => $DHT11->read,
        }});
    });
};

app->start;

sub hide_keyboard {
    system qw{dbus-send --type=method_call --print-reply --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Hide};
}
sub show_keyboard {
    system qw{dbus-send --type=method_call --print-reply --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Show};
}


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

    #button-shutdown {
        font-size: 200%;
        color: #fff;
        text-decoration: none!important;
        background: #f00;
        position: absolute;
        left: 0;
        top: 135px;
        display: block;
        line-height: 40px;
        height: 40px;
        width: 40px;
        padding-right: 5px;
        letter-spacing: -.55em;
        font-family: sans-serif;
        border: 1px solid #000;
    }

    #button-reload-page {
        font-size: 200%;
        color: #000;
        text-decoration: none!important;
        background: #ccf;
        position: absolute;
        left: 0;
        top: 260px;
        display: block;
        line-height: 40px;
        height: 40px;
        width: 40px;
        font-family: sans-serif;
        border: 1px solid #000;
    }

    #button-reboot {
        font-size: 200%;
        color: #000;
        text-decoration: none!important;
        background: #cc0;
        position: absolute;
        left: 0;
        top: 390px;
        display: block;
        line-height: 40px;
        height: 40px;
        width: 40px;
        font-family: sans-serif;
        border: 1px solid #000;
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
        width: calc(100%/6 - 1px);
        font-size: 200%;
        color: black;
        text-decoration: none!important;
        border-right: 1px solid #000;
        display: inline-block;
        height: 40px;
        line-height: 40px;
    }
    #brightness a:last-child { border-right: 0 }


    #sensors {
        width: 399px;
        height: 40px;
        line-height: 40px;
        position: absolute;
        left: 400px;
        top: 0px;
        background: #dfd;
        text-align: left;
        font-size: 120%;
        font-weight: bold;
    }

    #sugar-voltage {
        position: absolute;
        left: 10px;
        top: 0;
    }
    #sugar-percent {
        position: absolute;
        left: 65px;
        top: 0;
    }
    #sensor-light {
        position: absolute;
        left: 150px;
        top: 0;
    }
    #sensor-uv {
        position: absolute;
        left: 210px;
        top: 0;
    }
    #sensor-temp {
        position: absolute;
        left: 250px;
        top: 0;
    }
    #sensor-humidity {
        position: absolute;
        left: 310px;
        top: 0;
    }

    #wifi {
        width: 399px;
        height: 399px;
        position: absolute;
        left: 400px;
        top: 40px;
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

    #accel {
        position: absolute;
        display: inline-block;
        left: 112px;
        height: 160px;
        width: 160px;
        bottom: 102px;
        background: none;
        border-radius: 50%;
        border: 10px solid #00d;
        z-index: 20;
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
        <a href="?shutdown=1" id="button-shutdown"
          class="ajax-button">IO</a>

        <a href="#" id="button-reload-page"
            onclick="window.location.reload()">⟳</a>

        <a href="?reboot=1"   id="button-reboot"
          class="ajax-button">↻</a>
        <div id="info-sats"></div>
        <div id="info-speed"></div>
        <div id="info-climb"></div>
        <div id="info-lat"></div>
        <div id="info-lon"></div>
        <div id="info-alt"></div>

        <div id="accel"></div>

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
      ><a href="?show_kbd=1"     id="show-kbd" class="ajax-button">✓⌨</a
      ><a href="?hide_kbd=1"     id="hide-kbd" class="ajax-button">✘⌨</a
      ><a href="?brightness=9"   id="brightness-night"
        class="ajax-button">★</a
      ><a href="?brightness=15"  id="brightness-night"
        class="ajax-button">☆</a
      ><a href="?brightness=80"  id="brightness-cloudy"
        class="ajax-button">☁</a
      ><a href="?brightness=255" id="brightness-sunny"
        class="ajax-button">☀</a
    ></div>

    <div id="sensors">
        <div id="sugar-voltage"></div>
        <div id="sugar-percent"></div>
        <div id="sensor-light"></div>
        <div id="sensor-uv"></div>
        <div id="sensor-temp"></div>
        <div id="sensor-humidity"></div>
    </div>

    <div id="wifi">
        <div id="wifi-n"></div>
        <div id="wifi-open"></div>
        <div id="wifi-all"></div>
    </div>

    <div id="debug"></div>
</div>


<script>
    //if ( ! window.fullScreen) {
      document.documentElement.requestFullscreen()
        .catch(error =>  console.log(error));
    //}

    var btns = document.getElementsByClassName('ajax-button');
    for (var i = 0, l = btns.length; i < l; i++) {
      btns[i].onclick = function(e) {
          e.preventDefault();
          callAjax(this.href);
          this.blur();
          return false;
      }
    }

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

        // marginTop did not work apparently because we use `bottom`
        byid('accel').style.marginBottom  = (data.accel.y*-60) + 'px';
        byid('accel').style.marginLeft    = (data.accel.x*-60) + 'px';

        byid('sugar-voltage').innerHTML = data.sugar.battery_voltage + 'V';
        byid('sugar-percent').innerHTML = data.sugar.battery_percent
            + '%' + (data.sugar.is_charging ? '↯' : '');

        byid('sensor-light').innerHTML = "\u{1F4A1}" + data.light.raw;
        byid('sensor-uv').innerHTML = "\u{2600}" + data.uv.raw;
        byid('sensor-temp').innerHTML = "\u{1F321}" + data.dht11.temp;
        byid('sensor-humidity').innerHTML = "\u{1F4A7}" + data.dht11.humidity;


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

        //byid('debug').innerHTML = event.data;

        ws.send('poll')
    };
    ws.onopen = function (event) {
        ws.send('poll')
    };

    function callAjax(url, callback){
        var xmlhttp;
        xmlhttp = new XMLHttpRequest();
        xmlhttp.onreadystatechange = function(){
            if (callback && xmlhttp.readyState == 4 && xmlhttp.status == 200){
                callback(xmlhttp.responseText);
            }
        }
        xmlhttp.open("GET", url, true);
        xmlhttp.send();
    }
</script>