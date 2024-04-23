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

with 'TTP::Findable', 'TTP::JSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# hardcoded subpaths to find the <node>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => [
		'etc/nodes',
		'nodes',
		'etc/machines',
		'machines'
	]
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Whether the currenly being loaded JSON is acceptable as an execution node
# If the node is disabled, then we refuse to load it
# (I):
# - the raw loaded data
# (O):
# - returns true if we accept that as a valid node, or false else

sub _acceptable {
	my ( $self, $path ) = @_;
	my $enabled = true;
	my $data = $self->jsonRead( $path );
	$enabled = $data->{enabled} if exists $data->{enabled};
	#print __PACKAGE__."::_acceptable() path='$path' enabled='$enabled'".EOL;
	return $enabled;
}

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

	return $self->jsonSuccess();
}

### Class methods

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
	my $dirs = $ttp->var( 'nodesDirs' ) || TTP::Node->finder();
	my $success = $self->jsonLoad({ spec => [ $dirs, "$node.json" ], accept => sub { $self->_acceptable( @_ ) }});

	# unable to find and load the node configuration file ? this is an unrecoverable error
	my $abort = true;
	$abort = $args->{abortOnError} if exists $args->{abortOnError};
	if( !$success && $abort ){
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

# -------------------------------------------------------------------------------------------------
# Publish the list of dirs here nodes are to be found
# Can be called both as 'TTP::Node->finder()' or as 'TTP::Node::finder()' as we do not manage any
# argument here.
# (I]:
# - none
# (O):
# - Returns the Const->{finder} specification as an array ref

sub finder {
	return $Const->{finder};
}

1;

__END__
