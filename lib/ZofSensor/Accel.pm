package ZofSensor::Accel;

# keyestudio "accelerometer" sensor

use Mojo::Base -base;
use 5.020;
use Mojo::Collection qw/c/;
use Device::SMBus;
use Time::HiRes qw//;
use ZofSensor::Accel::Reading;

has 'dev_addr' => 0x1d;
has 'dev_path' => '/dev/i2c-3';
has 'smooth_over_seconds' => 1;
has '_readings' => sub { c };
has [qw/_dev/];
has [qw/x_correction  y_correction  z_correction/] => 0;

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->_setup_accel;
    $self->save_correction;
    $self
}

sub read {
    my $self = shift;
    my $t = Time::HiRes::time;
    $self->_readings($self->_readings
        ->grep(sub { $t - $_->time <= $self->smooth_over_seconds }));
    push $self->_readings->@*, $self->_read_accel;
    my ($x, $y, $z) = (0, 0, 0);
    for ($self->_readings->each) {
        $x += $_->x; $y += $_->y; $z += $_->z;
    }
    $_ = $_/$self->_readings->size for $x, $y, $z;
    +{ x => $x, y => $y, z => $z }
}

sub save_correction {
    my $self = shift;
    my $reading = $self->_read_accel(no_correction => 1);
    $self->x_correction($reading->x);
    $self->y_correction($reading->y);
    $self->z_correction(1-$reading->z); # z is expected to have 1g
}

sub _setup_accel {
    my $self = shift;
    my $dev = Device::SMBus->new(
        I2CBusDevicePath => $self->dev_path,
        I2CDeviceAddress => $self->dev_addr,
    );

    # MMA8452Q address, 0x1C(28)
    # Select Control register, 0x2A(42)
    #       0x00(00)    StandBy mode
    #bus.write_byte_data(ACCEL_ADDR, 0x2A, 0x00)
    $dev->writeByteData(0x2A, 0x00);

    # MMA8452Q address, 0x1C(28)
    # Select Configuration register, 0x0E(14)
    #       0x00(00)    Set range to +/- 2g
    #bus.write_byte_data(0x1C, 0x0E, 0x00)
    $dev->writeByteData(0x0E, 0x00); #apparently 0x00 = -/+2G, 0x01 = 4G, 0x10 = 8G

    # MMA8452Q address, 0x1C(28)
    # Select Control register, 0x2A(42)
    #       0x01(01)    Active mode
    #bus.write_byte_data(0x1C, 0x2A, 0x01)
    $dev->writeByteData(0x2A, 0x01);

    $self->_dev($dev)
}

sub _read_accel {
    my ($self, %args) = @_;
    # MMA8452Q address, 0x1C(28)
    # Read data back from 0x00(0), 7 bytes
    # Status register, X-Axis MSB, X-Axis LSB, Y-Axis MSB, Y-Axis LSB, Z-Axis MSB, Z-Axis LSB
    #data = bus.read_i2c_block_data(0x1C, 0x00, 7)
    my ($status, $xm, $xl, $ym, $yl, $zm, $zl)
        = $self->_dev->readBlockData(0x00,7);

    my $x = ($xm*256+$xl)/16; $x -= 4096 if $x > 2047;
    my $y = ($ym*256+$yl)/16; $y -= 4096 if $y > 2047;
    my $z = ($zm*256+$zl)/16; $z -= 4096 if $z > 2047;
    $_ /= 1000 for $x, $y, $z;

    unless ($args{no_correction}) {
        $x -= $self->x_correction;
        $y -= $self->y_correction;
        $z -= $self->z_correction;
    }

    ZofSensor::Accel::Reading->new(x => $x, y => $y, z => $z,
        time => Time::HiRes::time);
}


1;
__END__
