package ZofSensor::HT16K33LED8x8Matrix;

# Keyestudio HT16K33 8x8 LED Matrix

use Mojo::Base -base;
use 5.020;
use Mojo::Collection qw/c/;
use Device::SMBus;
use Carp qw/croak/;

has 'dev_addr' => 0x70;
has 'dev_path' => '/dev/i2c-4';
has [qw/_dev/];
has _mattrix => sub {[
    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],

    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],
    [0, 0, 0, 0,  0, 0, 0, 0],
]};

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->_setup_matrix;
    $self
}

# sub read {
#     my $self = shift;
#     +{
#         battery_percent_precise => $self->_read_battery_percent,
#         battery_voltage_precise => $self->_read_voltage,
#         battery_percent => sprintf('%.2f', $self->_read_battery_percent||0),
#         battery_voltage => sprintf('%.2f', $self->_read_voltage||0),
#         is_charging     => $self->_read_is_charging,
#     }
# }

# https://emalliab.wordpress.com/tag/i2ctools/
sub _setup_matrix {
    my $self = shift;
    my $dev = Device::SMBus->new(
        I2CBusDevicePath => $self->dev_path,
        I2CDeviceAddress => $self->dev_addr,
    );

    # initialization
    # "turns on the oscillator – setting bit S in the “system setup” register – labelled D8 in the data sheet"
    $dev->writeByte(0x21);

    # "enables the display with no blinking – setting bit D in the “display setup register” – D8 again in the data sheet.  To enable blinking then B1+B0 must be set to 01, 10 or 11 – i.e. replace 0x81 with 0x83, 0x85 or 0x87 respectively"
    $dev->writeByte(0x81);

    # "sets the brightness level – in this case, leaving the brightness to the dimmest setting, P0, P1, P2, P3 are all zero in the “digital dimming data input”.  Use a different value instead of 0 in the 0xe0 value – e.g. 0xef would be the brightest setting (all 1s)."
    $dev->writeByte(0xe0);
    $self->_dev($dev);
    $self->_print_matrix;
}

sub _print_matrix {
    my $self = shift;
    my $m = $self->_mattrix;
    # from https://emalliab.wordpress.com/tag/i2ctools/
    my @y_addr = (0x80, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40);
    for my $x (0..7) {
        my $y_combined = 0;
        for my $y (0..7) {
            $y_combined |= $y_addr[$y] if $m->[$x][$y];
        }
        $self->_dev->writeByteData($x*2, $y_combined);
    }
}

# $v = true (on); false (off)
sub set_one {
    my ($self, $v, $x, $y) = @_;
    croak "X out of range 1-8" if $x < 1 or $x > 8;
    croak "Y out of range 1-8" if $y < 1 or $y > 8;
    $self->_mattrix->[$x-1][$y-1] = $v ? 1 : 0;
    $self->_print_matrix;
}

sub set_row {
    my ($self, $v, $x) = @_;
    croak "X out of range 1-8" if $x < 1 or $x > 8;
    $self->_mattrix->[$x-1] = [ ($v ? 1 : 0) x 8 ];
    $self->_print_matrix;
}

sub set_col {
    my ($self, $v, $y) = @_;
    croak "Y out of range 1-8" if $y < 1 or $y > 8;
    $_->[$y-1] = $v ? 1 : 0 for $self->_mattrix->@*;
    $self->_print_matrix;
}

sub clear {
    my $self = shift;
    $self->_dev->writeByteData($_, 0x00) for grep 0 == $_ % 2, 0x00..0x0e;
}

sub turn_off {
    my $self = shift;

    $self->_dev->writeByte(0x20);
    $self->_dev->writeByte(0x80);
}


1;
__END__
