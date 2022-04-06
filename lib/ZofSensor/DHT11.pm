package ZofSensor::DHT11;

# Ks0098 keyestudio TEMT6000 Ambient Light Sensor

use Mojo::Base -base;
use 5.020;
use Mojo::JSON qw/from_json/;
use Fcntl ':flock';
use Time::HiRes qw//;

use constant TOO_OLD_DATA => 10; # seconds

# Sensor is too damn slow to read from so we have a separate job run
# cron/temp-humidity.pl script to read it and
# and we just read from the file it writes into

has 'cron_data_file';

sub read {
    my $self = shift;
    open my $fh, '<', $self->cron_data_file or do {
        warn "Could not open data file $!";
        next;
    };

    flock $fh, LOCK_SH or do {
        warn "Could not lock data file $!";
        next;
    };

    my $data = eval { from_json do { undef $/; <$fh> } } || {};
    if (Time::HiRes::time() - ($data->{time}||0) > TOO_OLD_DATA) {
        $data->{humidity} = -100;
        $data->{temp}     = -100;
    }
    $data
}

1;
__END__