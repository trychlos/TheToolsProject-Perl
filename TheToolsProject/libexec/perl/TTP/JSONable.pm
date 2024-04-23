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
# A role for classes which have a JSON configuration file.
#
# Note: JSON configuration files are allowed to embed some dynamically evaluated Perl code.
# As the evaluation is executed here, this module may have to 'use' the needed Perl packages
# which are not yet in the running context.

package TTP::JSONable;
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use File::Spec;
use JSON;
use Test::Deep;
use Time::Piece;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### Private methods
### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

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
	my $ref = ref( $value );
	if( !$ref ){
		$result = $self->_evaluateScalar( $value );
	} elsif( $ref eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$value} ){
			push( @{$result}, $self->_evaluateRec( $it ));
		}
	} elsif( $ref eq 'HASH' ){
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
	my $ref = ref( $value );
	my $evaluate = true;
	if( $ref ){
		msgErr( __PACKAGE__."::_evaluateScalar() scalar expected, but '$ref' found" );
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
	#print __PACKAGE__."::_evaluatePrint() value='$value' result='$result'".EOL;
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
	$self->{_jsonable}{evaluated} = $self->{_jsonable}{raw};
	$self->{_jsonable}{evaluated} = $self->_evaluate( $self->{_jsonable}{raw} );
}

# -------------------------------------------------------------------------------------------------
# Returns the evaluated data
# (I]:
# - none
# (O):
# - the evaluated data

sub jsonData {
	my ( $self, $args ) = @_;

	return $self->{_jsonable}{evaluated};
}

# -------------------------------------------------------------------------------------------------
# Load the specified JSON configuration file
# (I]:
# - an argument object with following keys:
#   > spec: the specification to be searched for in TTP_ROOTS tree, as a scalar or as an array ref
#     or as an array of array refs
#   or:
#   > path: the absolute exact path to be loaded
# (O):
# - true if a file or the specified file has been found and successfully loaded
# 

sub jsonLoad {
	my ( $self, $args ) = @_;
	$args //= {};

	# keep the passed-in args
	$self->{_jsonable}{spec} = $args->{spec} if $args->{spec};
	$self->{_jsonable}{path} = $args->{path} if $args->{path};

	# if a path is specified, the we want this one absolutely
	if( $self->{_jsonable}{path} ){
		$self->{_jsonable}{json} = $self->{_jsonable}{path};
	# else find the first suitable file in TTP_ROOTS and keep its path
	} else {
		$self->{_jsonable}{json} = $self->find( $args ) if $args->{spec};
	}

	# load the raw JSON data
	my $result = undef;
	$result = $self->jsonRead( $self->{_jsonable}{json} ) if $self->{_jsonable}{json};
	$self->{_jsonable}{loaded} = defined( $result );

	# initialize the evaluated part, even if not actually evaluated, so that jsonData()
	# can at least returns raw - unevaluated - data
	#$self->{_jsonable}{evaluated} = $self->{_jsonable}{raw};

	return $self->{_jsonable}{loaded};
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file raw data
# (I):
# - the full path to the to-be-loaded json file
# (O):
# returns the read hash, or undef (most probably in case of a JSON syntax error)

sub jsonRead {
	my ( $self, $path ) = @_;
	TTP::stackTrace() if !$path;
	msgVerbose( __PACKAGE__."::jsonRead() path='$path'" );
	#print __PACKAGE__."::jsonRead() path='$path'".EOL;
	my $result = undef;
	if( $path && -r $path ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $path ) or msgErr( __PACKAGE__."::jsonRead() $path: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		# may croak on error, intercepted below
		eval { $result = $json->decode( $content ) };
		if( $@ ){
			msgWarn( __PACKAGE__."::jsonRead() $path: $@" );
			$result = undef;
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Says if the JSON raw data has been successfully loaded
# (I]:
# - none
# (O):
# - true|false

sub jsonSuccess {
	my ( $self ) = @_;

	return $self->{_jsonable}{loaded};
}

# -------------------------------------------------------------------------------------------------
# JSONable initialization
# Initialization of a command or of an external script
# (I):
# - the TTP EntryPoint ref
# (O):
# -none

after _newBase => sub {
	my ( $self, $ttp ) = @_;

	$self->{_jsonable} //= {};
};

### Global functions

1;

__END__
