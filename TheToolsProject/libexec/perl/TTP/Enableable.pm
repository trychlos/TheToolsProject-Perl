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
# Enable a JSON file.
#
# Syntax:
#   "enabled": true|false
#
# Most of JSON configuration files can be enabled or disabled.
# The (hardcoded) default is to enable the configuration, and hence the underlying configured
# object.

package TTP::Enableable;
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
# Find the first file which matches the given specification by walking through TTP_ROOTS
# (I]:
# - an argument object with following keys:
#   > spec: the specification to be searched for in TTP_ROOTS tree
#     as a scalar, or as a ref to an array of items which have to be concatenated,
#     when each item for the array may itself be an array of scalars to be sucessively tested
#   > accept: a code reference which will receive the full path of the candidate, and must return
#     true|false to accept or refuse this file
#     defaults to true if accept is not specified
# (O):
# - the full pathname of a found and accepted file

sub enabled {
	my ( $self, $args ) = @_;
	my $result = undef;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Enableable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_enableable} //= {};
	$self->{_enableable}{enabled} = true;
};

1;

__END__
