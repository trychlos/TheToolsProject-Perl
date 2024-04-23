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
# The base class common to classes which are JSON-configurable
#
# Note: JSON configuration files are allowed to embed some dynamically evaluated Perl code.
# As the evaluation is executed here, this module must 'use' all needed Perl packages.

package TTP::JSONable;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use JSON;
use Role::Tiny::With;
use Test::Deep;
use Time::Piece;

with 'TTP::Findable';

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### Private methods

# -------------------------------------------------------------------------------------------------
# recursively interpret the provided data for variables and computings
#  and restart until all references have been replaced
# (I):
# - a hash object to be evaluated
# (O):
# - the evaluated hash object

sub _evaluate {
	my ( $self, $value ) = @_;
	my %prev = ();
	my $result = $self->_evaluateRec( $value );
	if( $result ){
		while( !eq_deeply( $result, \%prev )){
			%prev = %{$result};
			$result = $self->_evaluateRec( $result );
		}
	}
	return $result;
}

sub _evaluateRec {
	my ( $self, $value ) = @_;
	my $result = '';
	my $type = ref( $value );
	if( !$type ){
		$result = $self->_evaluateScalar( $value );
	} elsif( $type eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$value} ){
			push( @{$result}, $self->_evaluateRec( $it ));
		}
	} elsif( $type eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$value} ){
			$result->{$key} = $self->_evaluateRec( $value->{$key} );
		}
	} else {
		$result = $value;
	}
	return $result;
}

sub _evaluateScalar {
	my ( $self, $value ) = @_;
	my $type = ref( $value );
	my $evaluate = true;
	if( $type ){
		msgErr( __PACKAGE__."::_evaluateScalar() scalar expected, but '$type' found" );
		$evaluate = false;
	}
	my $result = $value || '';
	if( $evaluate ){
		my $re = qr/
			[^\[]*	# anything which doesn't contain any '['
			|
			[^\[]* \[(?>[^\[\]]|(?R))*\] [^\[]*
		/x;

		# debug code
		if( false ){
			my @matches = $result =~ /\[eval:($re)\]/g;
			print "line='$result'".EOL;
			print Dumper( @matches );
		}

		# this weird code to let us manage some level of pseudo recursivity
		$result =~ s/\[eval:($re)\]/$self->_evaluatePrint( $1 )/eg;
		$result =~ s/\[_eval:/[eval:/g;
		$result =~ s/\[__eval:/[_eval:/g;
		$result =~ s/\[___eval:/[__eval:/g;
		$result =~ s/\[____eval:/[___eval:/g;
		$result =~ s/\[_____eval:/[____eval:/g;
	}
	return $result;
}

sub _evaluatePrint {
	my ( $self, $value ) = @_;
	my $result = eval $value;
	# we cannot really emit a warning here as it is possible that we are in the way of resolving
	# a still-undefined value. so have to wait until the end to resolve all values, but too late
	# to emit a warning ?
	#msgWarn( "something is wrong with '$value' as evaluation result is undefined" ) if !defined $result;
	$result = $result || '(undef)';
	#print "value='$value' result='$result'".EOL;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file raw data
# (I):
# - the full path to the to-be-loaded json file
# (O):
# returns the read hash, or undef (most probably in case of a JSON syntax error)

sub _read {
	my ( $self, $path ) = @_;
	msgVerbose( __PACKAGE__."::_read() path='$path'" );
	my $result = undef;
	if( $path && -r $path ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $path ) or msgErr( __PACKAGE__."::_read() $path: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		# may croak on error
		eval { $result = $json->decode( $content ) };
		if( $@ ){
			msgWarn( __PACKAGE__."::_read() $path: $@" );
		} else {
			$self->{_loaded} = true;
		}
	}
	return $result;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Evaluates the raw data in this Perl context
# (I]:
# - none
# (O):
# - nothing

sub evaluate {
	my ( $self, $args ) = @_;
	$self->{_evaluated} = $self->{_raw};
	$self->{_evaluated} = $self->_evaluate( $self->{_raw} );
}

# -------------------------------------------------------------------------------------------------
# Returns the evaluated data
# (I]:
# - none
# (O):
# - the evaluated data

sub get {
	my ( $self, $args ) = @_;

	return $self->{_evaluated};
}

# -------------------------------------------------------------------------------------------------
# Says if the JSON raw data has been successfully loaded
# (I]:
# - none
# (O):
# - true|false

sub success {
	my ( $self, $args ) = @_;
	return $self->{_loaded};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > spec: the specification to be searched for in TTP_ROOTS tree, as a scalar or as an array ref
#   or:
#   > path: the exact path to be loaded
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	my $self = $class->SUPER::new( $ttp, $args );
	bless $self, $class;

	$args //= {};
	# keep the passed-in args
	$self->{_spec} = $args->{spec} if $args->{spec};
	$self->{_path} = $args->{path} if $args->{path};

	# if a path is specified, the we want this one absolutely
	if( $self->{_path} ){
		$self->{_json} = $self->{_path};
	# else find the first suitable file in TTP_ROOTS and keep its path
	} else {
		$self->{_json} = $self->find( $args ) if $self->{_spec};
	}

	# load the raw JSON data
	$self->{_loaded} = false;
	$self->{_raw} = $self->_read( $self->{_json} ) if $self->{_json};

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
