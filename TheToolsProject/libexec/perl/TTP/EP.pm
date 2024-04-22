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
# -

sub bootstrap {
	my ( $self, $args ) = @_;

	# first identify, load, evaluate the site configuration - exit if error
	my $site = TTP::Site->new( $self );
	$self->{_site} = $site;
	$site->evaluate();

	# identify current host (remind that there is no logical node in this Perl version)
	my $node = TTP::Node->new( $self );
	$self->{_node} = $node;
	$node->evaluate();

	msgLog( "executing $0 ".join( ' ', @ARGV ));
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
# - the hash ref to be searched for
# (O):
# - the evaluated value of this variable, which may be undef

sub var {
	my ( $self, $keys, $base ) = @_;
	my $found = undef;
	if( $base ){
		$found = $self->_var_rec( $keys, $base );
	} else {
		my $object = $self->node();
		$found = $self->var( $keys, $object->get()) if !$found && $object;
		$object = $self->site();
		$found = $self->var( $keys, $object->get()) if !$found && $object;
	}
	return $found;
}

# keys is a scalar, or an array of scalars, or an array of arrays of scalars
sub _var_rec {
	my ( $self, $keys, $base, $startBase ) = @_;
	return $base if !ref( $base );
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
					last if $base;
				}
			} elsif( $ref ){
				msgErr( __PACKAGE__."::_var_rec() unexpected intermediate ref='$ref'" );
			} else {
				$base = $self->_var_rec( $k, $base, $startBase );
			}
		}
	} elsif( $ref ){
		msgErr( __PACKAGE__."::_var_rec() unexpected final ref='$ref'" );
	} else {
		# the key here may be empty when targeting the top of the hash
		$base = $keys ? ( $base->{$keys} || undef ) : $base;
	}
	#print "returning '".( $base ? $base : '(undef)' )."'".EOL;
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
