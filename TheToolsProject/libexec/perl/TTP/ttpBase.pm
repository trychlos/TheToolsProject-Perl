# Copyright (@) 2023-2024 PWI Consulting
#
# The base class for all TTP classes

package ttpBase;

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

	my $self = {};
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
	#print "L'objet de la classe " . __PACKAGE__ . " va mourir\n";
	return;
}

1;

__END__
