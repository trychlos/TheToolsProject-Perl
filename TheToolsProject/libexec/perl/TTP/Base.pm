# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 2003-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.
#
# The base class for all TTP classes

package TTP::Base;

our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;

### Private methods

### Public methods

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - none
# (O):
# - this object

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
