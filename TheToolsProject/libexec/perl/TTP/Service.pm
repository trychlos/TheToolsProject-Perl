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
# - Even if the node doesn't want override any service key, it still MUST define the service in the
#   'Services' object of its own configuration file

package TTP::Service;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Role::Tiny::With;
use vars::global qw( $ttp );

with 'TTP::IEnableable', 'TTP::IFindable', 'TTP::IJSONable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Node;

my $Const = {
	# hardcoded subpaths to find the <service>.json files
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	finder => {
		dirs => [
			'etc/services',
			'services'
		],
		sufix => '.json'
	}
};

### Private methods

### Public methods

# ------------------------------------------------------------------------------------------------
# Returns the name of the service
# (I):
# -none
# (O):
# - returns the name of the service, or undef

sub name {
	my ( $self ) = @_;

	return $self->{_name};
}

# ------------------------------------------------------------------------------------------------
# Returns the value of the specified var.
# The var is successively searched for in the Node configuration, then in this Service configuration
# and last at the site level.
# (I):
# - a ref to the array of successive keys to be addressed
# - an optional node to be searched for, defaulting to current execution node
#   the node can be specified either as a string (the node name) or a TTP::Node object
# (O):
# - returns the found value, or undef

sub var {
	my ( $self, $args, $node ) = @_;
	# keep a copy of the provided arguments
	my @args = @{$args};
	my $name = $self->name();
	my $value = undef;
	my $jsonable = undef;
	# do we have a provided node ?
	if( $node ){
		my $ref = ref( $node );
		if( $ref ){
			if( $ref eq 'TTP::Node' ){
				$jsonable = $node;
			} else {
				msgErr( __PACKAGE__."::var() expects node be provided either by name or as a 'TTP::Node', found '$ref'" );
			}
		} else {
			my $nodeObj = TTP::Node->new( $ttp, { node => $node });
			if( $nodeObj->loaded()){
				$jsonable = $nodeObj;
			}
		}
	} else {
		$jsonable = $ttp->node();
	}
	if( $jsonable ){
		# search for the service definition in the node
		unshift( @{$args}, [ 'Services', $name ] );
		$value = $jsonable->var( $args );
		# search as the value general to the node
		if( !defined( $value )){
			$value = $jsonable->var( \@args );
		}
		# search in this service definition
		if( !defined( $value )){
			$value = $self->TTP::IJSONable::var( \@args );
		}
		# last search for a default value at site level
		if( !defined( $value )){
			$value = $ttp->site()->var( \@args );
		}
	}
	return $value;
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find services configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON services configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ttp->var( 'servicesDirs' ) || $class->finder()->{dirs};

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
# - the TTP EP entry point ref
# - an arguments hash with following keys:
#   > service: the service name to be initialized
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp, $args );
	bless $self, $class;

	if( $args->{service} ){

		# keep the service name
		$self->{_name} = $args->{service};

		# allowed servicesDirs are configured at site-level
		my $findable = {
			dirs => [ $class->dirs(), $args->{service}.$class->finder()->{sufix} ],
			wantsAll => false
		};
		my $acceptable = {
			accept => sub { return $self->enabled( @_ ); },
			opts => {
				type => 'JSON'
			}
		};
		$self->jsonLoad({ findable => $findable, acceptable => $acceptable });

	} else {
		msgErr( __PACKAGE__."::new() expects an 'args->{service}' key, which has not been found" );
	}

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
