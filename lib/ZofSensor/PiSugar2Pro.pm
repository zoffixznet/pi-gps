package ZofSensor::PiSugar2Pro;

# keyestudio "accelerometer" sensor

use Mojo::Base -base;
use 5.020;
use Mojo::Collection qw/c/;
use Device::SMBus;

has 'dev_addr' => 0x75;
has 'dev_path' => '/dev/i2c-1';
has [qw/_dev/];

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->_setup_battery;
    $self
}

sub read {
    my $self = shift;
    +{
        battery_percent => $self->_read_battery_percent,
        battery_voltage => $self->_read_voltage,
        is_charging     => $self->_read_is_charging,
    }
}

sub _setup_battery {
    my $self = shift;
    my $dev = Device::SMBus->new(
        I2CBusDevicePath => $self->dev_path,
        I2CDeviceAddress => $self->dev_addr,
    );
    $self->_dev($dev)
}

# https://github.com/PiSugar/PiSugar/wiki/PiSugar-2-%28Pro%29-I2C-Manual#step-4--read-registers-0xdc-and-0xdd
sub _read_is_charging {
    my $self = shift;
    if (    $self->_dev->readByteData(0xdc) == 0xff
        and $self->_dev->readByteData(0xdd) == 0x1f) {
        return 1
    }
    else {
        return 0
    }
}

# https://github.com/PiSugar/PiSugar/wiki/PiSugar-2-%28Pro%29-I2C-Manual#read-voltage-1
sub _read_voltage {
    my $self = shift;

    my $vl = $self->_dev->readByteData(0xd0);
    my $vh = $self->_dev->readByteData(0xd1);

    $vh &= 0b0011_1111; # highest two bits are reserved
    my $v = ($vh << 8) + $vl;
    ($v*0.26855+2600) / 1000; # adjustments based on Wiki info
}

sub _read_battery_percent {
    my $self = shift;

    # manually collected data { Voltage => battery % }
    my @battery_curve = (
        { 6          => 100},
        { 3.85385995 => 83 },
        { 3.83022755 => 80 },
        { 3.8025669  => 77 },
        { 3.7934362  => 76 },
        { 3.631232   => 64 },
        { 3.5060877  => 35 },
        { 0          => 0  },
    );

    my $v = $self->_read_voltage;
    my ($high_v, $high_p, $low_v, $low_p);
    for my $point (@battery_curve) {
        my ($bv, $bp) = %$point;
        if ($bv >= $v) {
            ($high_v, $high_p) = %$point;
        }
        elsif ($bv < $v) {
            ($low_v, $low_p) = %$point;
            last;
        }
    }

    my $rate_v = ($v - $low_v) / ($high_v - $low_v);
    ($rate_v * ($high_p - $low_p)) + $low_p
}

1;
__END__
