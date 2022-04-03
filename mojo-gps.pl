#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;

use lib qw/lib/;
use ZofGPS::GPSFrame;
use ZofGPS::Continuity;

use Mojolicious::Lite -signatures;

use GPS::NMEA;
my $GPS = GPS::NMEA->new(
    Port => '/dev/serial0',
    Baud => 9600, #19200, #38400, #115200, #9600,
);

get '/' => sub ($c) {
  $c->render(template => 'index');
};

my $Continuity = ZofGPS::Continuity->new;
websocket '/gps' => sub ($c) {
    $c->on(message => sub ($c, $msg) {
        $GPS->parse;
        $Continuity->add_frame(ZofGPS::GPSFrame->new($GPS->{NMEADATA}));
        $c->send({json => $Continuity->report});
    });
};

app->start;
__DATA__

@@ index.html.ep
<script>
    var last_stamp = 0;
    function byid(id) { return document.getElementById(id) }
    const ws = new WebSocket('<%= url_for("gps")->to_abs %>');
    ws.onmessage = function (event) {
        var data = JSON.parse(event.data);

        byid('lag').innerHTML = ((data.time||0)- last_stamp).toFixed(2)+'s';
        last_stamp = data.time||0;

        if (data.compass) {
          byid('needle').style.transform
            = 'rotate(' + (data.compass||0) + 'deg)';
        }
        byid('debug').innerHTML = event.data;

    };
    ws.onopen = function (event) {
        setInterval(function() { ws.send('poll') }, 1000)
    };
</script>
<style>
    body {
        padding: 40px;
        text-align: center;
    }
    #debug, #lag {
        font-size: 200%;
        font-weight: bold;
        text-align: center;
    }
    #debug {
        font-size: 120%;
    }
    #outer {
      position: relative;
      display: inline-block;
      height: 300px;
      width: 300px;
      margin: 40px auto;
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
    # #needle:after {
    #   content: "";
    #   position: absolute;
    #   top: calc(100% + 3px);
    #   left: 50%;
    #   height: 15px;
    #   width: 15px;
    #   transform: rotate(-135deg);
    #   transform-origin: top left;
    #   border-top: 3px solid black;
    #   border-left: 3px solid black;
    # }
    #outer:hover #needle {
      transform: rotate(-360deg);
      transform-origin: center center;
    }
</style>

<div id="lag"></div>

<div id="outer">
  <div id="needle"></div>
</div>

<div id="debug"></div>
