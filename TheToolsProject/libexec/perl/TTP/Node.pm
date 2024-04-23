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
# Manage the node configuration

package TTP::Node;

use base qw( TTP::JSONable );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Sys::Hostname qw( hostname );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpath to find the global site.json
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	dirs => [
		'etc/nodes',
		'nodes',
		'etc/machines',
		'machines'
	]
};

### Private methods

# -------------------------------------------------------------------------------------------------
# returns the hostname
# (I):
# - none
# (O):
# - returns the hostname
#   > as-is in *nix environments (including Darwin)
#   > in uppercase on Windows

sub _hostname {
	# not a method - just a function
	my $name = hostname;
	$name = uc $name if $Config{osname} eq 'MSWin32';
	return $name;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# returns the node name
# (I):
# - none
# (O):
# - returns the node name

sub name {
	my ( $self ) = @_;

	return $self->{_node};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the name of the targeted node, defaulting to current host
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	#print Dumper( @_ );

	# of which node are we talking about ?
	my $node = $args->{node} || _hostname();

	# allowed nodesDirs can be configured at site-level
	my $dirs = TTP::var( 'nodesDirs' ) || $Const->{dirs};
	#print Dumper( $dirs );

	my $self = $class->SUPER::new( $ttp, { spec => [ $dirs, "$node.json" ] });
	bless $self, $class;

	if( !$self->success()){
		msgErr( "Unable to find a valid execution node for '$node' in ".Dumper( $dirs ));
		msgErr( "Exiting with code 1" );
		exit( 1 );
	}

	# keep node name
	$self->{_node} = $node;

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
