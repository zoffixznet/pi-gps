package ZofSensor::LightSensor;

# Ks0098 keyestudio TEMT6000 Ambient Light Sensor

use Mojo::Base -base;
use 5.020;
use HiPi qw( :mcp3adc );
use HiPi::Interface::MCP3ADC;
use Time::HiRes qw//;

has dev  => '/dev/spidev0.0';
has ic   => MCP3008;
has chan => MCP3ADC_CHAN_0;
has _adc => sub {
    my $self = shift;
    HiPi::Interface::MCP3ADC->new(
        devicename   => $self->dev,
        ic           => $self->ic,
    );
};

sub read {
    my $self = shift;
    my $raw = $self->_adc->read($self->chan);
    +{ raw => $raw }
}

1;
__END__