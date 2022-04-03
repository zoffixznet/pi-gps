package ZofGPS::Continuity;

use 5.030;
use Mojo::Base -base;
use Mojo::Collection qw/c/;
use Time::HiRes qw//;
use Math::Trig qw/atan/;

use constant KEEP_PERIOD => 15; # seconds

has [qw/frames  last_lat  last_lon/] => sub { c };

sub add_frame {
    my ($self, $frame) = @_;
    push $self->frames->@*, $frame;
    $frame
}

sub report {
    my $self = shift;
    my $time = Time::HiRes::time;
    $self->frames($self->frames->grep(sub { $time - $_->time < KEEP_PERIOD }));
    +{
        time    => $time,
        compass => $self->compass,
        speed   => $self->_average('speed')
    }
}

sub compass {
    my $self = shift;

    my $lat = $self->_average('lat');
    my $lon = $self->_average('lon');

    my $dy = $self->last_lat - $lat;
    my $dx = $self->last_lon - $lon;
    $self->last_lat($lat);
    $self->last_lon($lon);

    my $deg = 180 / 3.1415926535; # 180/pi = rads to deg

          $dx == 0 && $dy == 0 ? 0
        : $dx == 0 ? ($dy > 0 ? 0  : 180)
        : $dy == 0 ? ($dx > 0 ? 90 : 270)
        : $dx > 0 && $dy > 0 ? atan( $dx /  $dy) * $deg       # Q1
        : $dx > 0 && $dy < 0 ? atan(-$dy /  $dx) * $deg + 90  # Q2
        : $dx < 0 && $dy < 0 ? atan(-$dx / -$dy) * $deg + 180 # Q3
        : $dx < 0 && $dy > 0 ? atan(-$dy /  $dx) * $deg + 270 : 0
}

sub _average {
    my ($self, $name) = @_;
    (my $frames = $self->frames->grep(sub { defined $_->$name }))->size
        or return 0;

    $frames->map(sub { $_->$name })->reduce(sub { $a + $b }) / $frames->size
}

1;
__END__