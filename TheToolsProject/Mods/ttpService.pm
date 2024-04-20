# Copyright (@) 2023-2024 PWI Consulting
#
# Manage services: an indirection level wanted to banalize instances and other resources between environments.
# E.g. given WS22DEV1.json and WS22PROD1.json configuration files, we are able to write, test and DEPLOY common scripts without any modification.
# In other words, the code must be the same. Only implementation details may vary, all these details being in json configurations.
#
# As of 2024-04-19, the service configuration can be written:
# - in a <service>.json configuration file
# - in a <hostname>.json configuration file, overriding the service-level items.
# Notes:
# - Service configuration file is optional, and may not exists for a service: the service may be entirely defined in hosts configuration files.
# - Even if the host doesn't want override any service key, it still MUST define the service in the "Services" object of its own configuration file.

package ttpService;

use base qw( ttpJSONable );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - an argument object with following keys:
#   > host context (object)
#   > service name (string)
# (O):

sub new {
	my ( $class, $args ) = @_;
	$class = ref( $class ) || $class;

	my $self = $class->SUPER::new( $args );
	bless $self, $class;
	
	$self->{host} = $args->{host};
	$self->{name} = $args->{name};
	
	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I]:
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY();
	return;
}

1;

__END__
