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
# The TTP global Entry Point, notably usable in configuration files to get up-to-date data

package TTP::EP;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;
use vars::global qw( $ttp );

use TTP::Command;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Node;
use TTP::Site;

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# TheToolsProject bootstrap process
# In this Perl version, we are unable to update the user environment with such things as TTP_ROOTS
# or TTP_NODE. So no logical machine paradigm and we stay stuck with current hostname.
# - read the toops+site and host configuration files and evaluate them before first use
# - initialize the logs internal variables
# (O):
# - returns this same object

sub bootstrap {
	my ( $self, $args ) = @_;

	# first identify, load, evaluate the site configuration - exit if error
	my $site = TTP::Site->new( $self );
	#print __PACKAGE__."::bootstrap() site allocated".EOL;
	$self->{_site} = $site;
	$site->evaluate();
	#print __PACKAGE__."::bootstrap() site evaluated and set".EOL;

	# identify current host (remind that there is no logical node in this Perl version)
	my $node = TTP::Node->new( $self );
	#print __PACKAGE__."::bootstrap() node allocated".EOL;
	$self->{_node} = $node;
	$node->evaluate();
	#print __PACKAGE__."::bootstrap() node evaluated and set".EOL;

	# reevaluate the site when the node is set
	$site->evaluate();

	return  $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the execution node context

sub node {
	my ( $self ) = @_;
	return $self->{_node};
}

# -------------------------------------------------------------------------------------------------
# Run the current command+verb
# (I):
# - none
# (O):
# - returns this same object

sub runCommand {
	my ( $self ) = @_;

	my $command = TTP::Command->new( $self );
	$command->run();

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the Runnable running command

sub running {
	my ( $self ) = @_;

	return $self->{_running};
}

# -------------------------------------------------------------------------------------------------
# Setter
# (I):
# - the Runnable running command
# (O):
# - this object

sub setRunning {
	my ( $self, $running ) = @_;

	$self->{_running} = $running;

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the site context, always defined

sub site {
	my ( $self ) = @_;
	return $self->{_site};
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the provided base
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each key can be itself an array ref of potential candidates for this level
# - the hash ref to be searched for,
#   defaulting to node, which itself default to site
# (O):
# - the evaluated value of this variable, which may be undef

my $varDebug = false;

sub var {
	my ( $self, $keys, $base ) = @_;
	#$varDebug = ( $keys eq 'logsRoot' || $keys eq 'nodeRoot' );
	print __PACKAGE__."::var() entering with keys='$keys' base='".( defined $base ? $base : '(undef)' )."'".EOL if $varDebug;
	my $found = undef;
	if( defined( $base )){
		$found = $self->_var_rec( $keys, $base );
	} else {
		# search in node if it is defined
		my $object = $self->node();
		$found = $self->var( $keys, $object->jsonData()) if !defined( $found ) && defined( $object );
		print  __PACKAGE__."::var() node is not set".EOL if $varDebug && !$object;
		#print  __PACKAGE__."::var() after node found='".( defined $found ? $found : '(undef)' )."'".EOL;
		# or search in the site for all known historical keys
		$object = $self->site();
		my @newKeys = ref $keys eq 'ARRAY' ? @{$keys} : ( $keys );
		unshift( @newKeys, [ '', 'toops', 'TTP' ] );
		$found = $self->var( \@newKeys, $object->jsonData()) if !defined( $found ) && defined( $object );
		print  __PACKAGE__."::var() site is not set".EOL if $varDebug && !$object;
		print  __PACKAGE__."::var() after site found='".( defined $found ? $found : '(undef)' )."'".EOL if $varDebug && $object;
	}
	return $found;
}

# keys is a scalar, or an array of scalars, or an array of arrays of scalars
sub _var_rec {
	my ( $self, $keys, $base, $startBase ) = @_;
	#print __PACKAGE__."::_var_rec() entering with keys='$keys' base='".( defined $base ? $base : '(undef)' )."'".EOL;
	return $base if !defined( $base ) || ref( $base ) ne 'HASH';
	$startBase = $startBase || $base;
	my $ref = ref( $keys );
	#print "keys=[".( ref( $keys ) eq 'ARRAY' ? join( ',', @{$keys} ) : $keys )."] base=$base".EOL;
	if( $ref eq 'ARRAY' ){
		for( my $i=0 ; $i<scalar @{$keys} ; ++$i ){
			my $k = $keys->[$i];
			$ref = ref( $k );
			if( $ref eq 'ARRAY' ){
				my @newKeys = @{$keys};
				for( my $j=0 ; $j<scalar @{$k} ; ++$j ){
					$newKeys[$i] = $k->[$j];
					$base = $startBase;
					$base = $self->_var_rec( \@newKeys, $base, $startBase );
					last if defined( $base );
				}
			} elsif( $ref ){
				msgErr( __PACKAGE__."::_var_rec() unexpected intermediate ref='$ref'" );
			} else {
				#print __PACKAGE__."::_var_rec() searching for '$k' key in $base".EOL;
				$base = $self->_var_rec( $k, $base, $startBase );
			}
		}
	} elsif( $ref ){
		msgErr( __PACKAGE__."::_var_rec() unexpected final ref='$ref'" );
	} else {
		# the key here may be empty when targeting the top of the hash
		$base = $keys ? $base->{$keys} : $base;
		#print __PACKAGE__."::_var_rec() keys='$keys' found '".( defined $base ? $base : '(undef)' )."'".EOL;
	}
	print __PACKAGE__."::_var_rec() returning '".( defined $base ? $base : '(undef)' )."'".EOL if $varDebug;
	return $base;
}

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
