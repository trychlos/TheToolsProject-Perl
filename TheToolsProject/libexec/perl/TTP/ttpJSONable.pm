# Copyright (@) 2023-2024 PWI Consulting
#
# The base class common to classes which are JSON-configurable

package ttpJSONable;

use base qw( ttpBase );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - an argument object with following keys:
#   > 
# (O):

sub new {
	my ( $class, $args ) = @_;
	$class = ref( $class ) || $class;

	my $self = $class->SUPER::new( $args );
	bless $self, $class;

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
