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
# Manage the node configuration

package TTP::Node;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;
use Sys::Hostname qw( hostname );
use vars::global qw( $ttp );

with 'TTP::Acceptable', 'TTP::Enableable', 'TTP::Findable', 'TTP::JSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpaths to find the <node>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/nodes',
			'nodes',
			'etc/machines',
			'machines'
		],
		sufix => '.json'
	}
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

# -------------------------------------------------------------------------------------------------
# returns whether the node has been successfully loaded
# (I):
# - none
# (O):
# - returns true|false

sub success {
	my ( $self ) = @_;

	return $self->jsonLoaded();
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find nodes configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON nodes configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ttp->var( 'nodesDirs' ) || $class->finder()->{dirs};

	return $dirs;
}

# -------------------------------------------------------------------------------------------------
# Returns the list of dirs where nodes are to be found
# (I]:
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > node: the name of the targeted node, defaulting to current host
#   > abortOnError: whether to abort if we do not found a suitable node JSON configuration,
#     defaulting to true
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp );
	bless $self, $class;

	# of which node are we talking about ?
	my $node = $args->{node} || _hostname();

	# allowed nodesDirs can be configured at site-level
	my $dirs = $class->dirs();
	my $findable = {
		dirs => [ $dirs, $node.$class->finder()->{sufix} ],
		wantsAll => false
	};
	my $acceptable = {
		accept => sub { return $self->enabled( @_ ); },
		opts => {
			type => 'JSON'
		}
	};
	my $loaded = $self->jsonLoad({ findable => $findable, acceptable => $acceptable });

	# unable to find and load the node configuration file ? this is an unrecoverable error
	# unless otherwise specified
	my $abort = true;
	$abort = $args->{abortOnError} if exists $args->{abortOnError};
	if( !$loaded && $abort ){
		msgErr( "Unable to find a valid execution node for '$node' in [".join( ',', @{$dirs} )."]" );
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

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

1;

__END__
