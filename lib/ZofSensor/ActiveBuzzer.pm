package ZofSensor::ActiveBuzzer;

# Keyestudio Active Buzzer

use Mojo::Base -base;
use 5.020;
use HiPi qw/:rpi/;
use HiPi::GPIO;
use Time::HiRes qw//;

has 'gpio'   => 26;
has _header  => sub { HiPi::GPIO->new };

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->_header->set_pin_mode($self->gpio, RPI_MODE_OUTPUT);
    $self
}

sub buzz_on {
    my $self = shift;
    $self->_header->set_pin_level($self->gpio, RPI_HIGH);
}
sub buzz_off {
    my $self = shift;
    $self->_header->set_pin_level($self->gpio, RPI_LOW);
}

sub buzz {
    my ($self, $duration) = @_;
    $self->buzz_on;
    Time::HiRes::sleep($duration||1);
    $self->buzz_off;
}


1;
__END__
