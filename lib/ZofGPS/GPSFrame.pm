package ZofGPS::GPSFrame;

use Mojo::Base -base;
use Time::HiRes qw//;
use constant DEBUG => 1;
has [qw/raw  time  lat  lon  speed/];

sub new {
    my ($self, $raw) = @_;
    my $prepped = __prep_raw($raw);
    use Acme::Dump::And::Dumper;
    warn DnD [ $raw, $prepped ] if DEBUG;
    $self->SUPER::new(
        raw => $raw,
        time => Time::HiRes::time,
        %$prepped{qw/lat  lon  speed /},
    )
}

sub __prep_raw {
    my $data = shift;
    my $res = +{
        speed  => ($data->{speed_over_ground}//0)*1.60934, # mph -> kmh
        course => $data->{course_made_good},
        ns     => $data->{lat_NS},
        ew     => $data->{lon_EW},
        lon    => $data->{lon_ddmm},
        lat    => $data->{lat_ddmm},
    };
    $_ = __arcm_to_deg($_) for @$res{qw/lon  lat/};

    if ($res->{ns} and $res->{ns} eq 'S' and length $res->{lat}) {
        $res->{lat} *= -1;
    }
    if ($res->{ew} and $res->{ew} eq 'W' and length $res->{lon}) {
        $res->{lon} *= -1;
    }

    return $res;
}


sub __arcm_to_deg {
    my $v = shift || 0;
    $v /= 100; # format is ddmm.mmmmm
    int($v) + ($v - int($v)) * 1.66666667;
}


1;
__END__
