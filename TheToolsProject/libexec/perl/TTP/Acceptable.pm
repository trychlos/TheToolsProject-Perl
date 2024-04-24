# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
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
# Whether a candidate object can be accepted by the implementation.
#
# This is notably used by the JSON configuration file-based classes as Site, Node, Service or Daemon
# to check if the file is enabled or not. From this point of view, the enabled property is an primary
# element of the acceptability decision.
#
# The accepted status is set to true at instanciation time.

package TTP::Acceptable;
our $VERSION = '1.00';

use strict;
use warnings;

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### Private methods

### Public methods
### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Test the specified file for acceptation
# (I]:
# - an arguments hash which must contain a 'acceptable' hash argument, with following keys:
#   >
# - the path to the to-be-tested file
# (O):
# - current accepted status of the object

sub accept {
	my ( $self, $file ) = @_;


	return $self->accepted();
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# (I]:
# - as a getter:
#   > none
# - as a setter
#   > a boolean which says whether the object is accepted or not
# (O):
# - current accepted status of the object

sub accepted {
	my ( $self, $newAccepted ) = @_;
	
	if( defined( $newAccepted )){
		$self->{_acceptable}{accepted} = ( $newAccepted ? true : false );
	}

	return $self->{_acceptable}{accepted};
}

# -------------------------------------------------------------------------------------------------
# Acceptable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_acceptable} //= {};
	$self->{_acceptable}{accepted} = true;
};

1;

__END__
