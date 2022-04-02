#!/usr/bin/env perl

use strict;
use warnings;
use 5.020;

use Mojolicious::Lite -signatures;

use GPS::NMEA;
use Time::HiRes qw//;
use Math::Trig qw/atan/;

my $GPS = GPS::NMEA->new(
    Port => '/dev/serial0',
    Baud => 9600, #19200, #38400, #115200, #9600,
);

get '/' => sub ($c) {
  $c->render(template => 'index');
};

websocket '/gps' => sub ($c) {
    $c->on(message => sub ($c, $msg) {
        my $data = _get_gps();
        use Acme::Dump::And::Dumper;
        # warn DnD $data;
        $c->send({json => $data});
    });
};

#sub _get_gps {
#     open my $fh, "<", "course" or die $!;
#     my $deg = <$fh>;
# }

my ($last_lon, $last_lat) = (0, 0);
sub _get_gps {
    $GPS->parse;
    my $data = $GPS->{NMEADATA};
    use Acme::Dump::And::Dumper;
    warn DnD [ $data ];
    my $res = +{
        stamp  => Time::HiRes::time,
        speed  => ($data->{speed_over_ground}//0)*1.60934, # mph -> kmh
        course => $data->{course_made_good},
        ns     => $data->{lat_NS},
        ew     => $data->{lon_EW},
        lon    => $data->{lon_ddmm},
        lat    => $data->{lat_ddmm},
    };
    $_ = _arcm_to_deg($_) for @$res{qw/lon  lat  course/};

    if ($res->{ns} and $res->{ns} eq 'S' and length $res->{lat}) {
        $res->{lat} *= -1;
    }
    if ($res->{ew} and $res->{ew} eq 'W' and length $res->{lon}) {
        $res->{lon} *= -1;
    }
    if (length $res->{lat} and length $res->{lon}) {
        my $dy = $last_lat - $res->{lat};
        my $dx = $last_lon - $res->{lon};
        $last_lat = $res->{lat};
        $last_lon = $res->{lon};

        $res->{dy} = $dy;
        $res->{dx} = $dx;
        my $deg = 180 / 3.1415926535; # 180/pi = rads to deg
        $res->{compass} =
              $dx == 0 && $dy == 0 ? 0
            : $dx == 0 ? ($dy > 0 ? 0  : 180)
            : $dy == 0 ? ($dx > 0 ? 90 : 270)
            : $dx > 0 && $dy > 0 ? atan( $dx /  $dy) * $deg       # Q1
            : $dx > 0 && $dy < 0 ? atan(-$dy /  $dx) * $deg + 90  # Q2
            : $dx < 0 && $dy < 0 ? atan(-$dx / -$dy) * $deg + 180 # Q3
            : $dx < 0 && $dy > 0 ? atan(-$dy /  $dx) * $deg + 270 : 0
        ;
    }

    return $res;
}

sub _arcm_to_deg {
    my $v = shift || 0;
    int($v) + ($v - int($v)) * 1.66666667;
}


app->start;
__DATA__

@@ index.html.ep
<script>
    var last_stamp = 0;
    function byid(id) { return document.getElementById(id) }
    const ws = new WebSocket('<%= url_for("gps")->to_abs %>');
    ws.onmessage = function (event) {
        var data = JSON.parse(event.data);

        byid('lag').innerHTML = ((data.stamp||0)- last_stamp).toFixed(2)+'s';
        last_stamp = data.stamp||0;
        
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
