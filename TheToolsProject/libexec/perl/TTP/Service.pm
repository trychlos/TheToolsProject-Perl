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
# Manage the service configurations.
#
# A service:
# - can be configured in an optional <service>.json file
# - must at least be mentionned in each and every <node>.json which manage or participate to the service.
# Note:
# - Even if the host doesn't want override any service key, it still MUST define the service in the 'Services' object of its own configuration file

package TTP::Service;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;

with 'TTP::Findable', 'TTP::JSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpaths to find the <service>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	dirs => [
		'etc/services',
		'services'
	]
};

### Private methods

### Public methods

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point ref
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp );
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

### Global functions

# -------------------------------------------------------------------------------------------------
# List the services defined a a given host
# (I]:
# - an optional node name, defaulting to the current execution node
# (O):
# - a ref to an array of the defined services

1;

__END__
