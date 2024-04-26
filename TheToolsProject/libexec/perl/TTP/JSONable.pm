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
# A role for classes which have a JSON configuration file.
#
# The jsonLoad() method is expected to be called at instanciation time with arguments:
# - json specifications
#   either as a 'finder' object to be provided to the Findable::find() method
#      in this case, find() will examine all specified files until having found an
#      accepted one (or none)
#   or as a 'path' object
#      in which case, this single object must also be an accepted one.
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
# This method is expected to be called at instanciation time.
#
# (I]:
# - an argument object with following keys:

#	> path: the path as a string
#     in which case, this single object must also be an accepted one
#   or
#   > findable: an arguments object to be passed to Findable::find() method
#     in this case, find() will examine all specified files until having found an accepted one (or none)
#   This is an unrecoverable error to have both 'findable' and 'path' in the arguments object
#   or to have none of these keys.
#
#   > acceptable: an arguments object to be passed to Acceptable::accept() method
#
# (O):
# - true if a file or the specified file has been found and successfully loaded
# 

sub jsonLoad {
	my ( $self, $args ) = @_;
	$args //= {};
	#print Dumper( $args );

	# keep the passed-in args
	$self->{_jsonable}{args} = \%{$args};

	# if a path is specified, the we want this one absolutely
	if( $args->{path} ){
		$self->{_jsonable}{json} = File::Spec->rel2abs( $args->{path} );
		if( $self->{_jsonable}{json} ){
			if( $self->does( 'TTP::Acceptable' ) && $args->{acceptable} ){
				$args->{acceptable}{object} = $args->{path};
				if( $self->accept( $args->{acceptable} )){
					$self->{_jsonable}{loadable} = true;
				}
			}
		}

	# else hope that the class is also a Findable
	# if a Findable, it will itself manages the Acceptable role
	} elsif( $self->does( 'TTP::Findable' ) && $args->{findable} ){
		my $res = $self->find( $args->{findable}, $args );
		if( $res ){
			my $ref = ref( $res );
			if( $ref eq 'ARRAY' ){
				$self->{_jsonable}{json} = $res->[0] if scalar @{$res};
			} elsif( !$ref ){
				$self->{_jsonable}{json} = $res;
			} else {
				msgErr( __PACKAGE__."::jsonLoad() expects scalar of array from Findable::find(), received '$ref'" );
			}
			$self->{_jsonable}{loadable} = true if $self->{_jsonable}{json};
		}

	# else we have no way to find the file: this is an unrecoverable error
	} else {
		msgErr( __PACKAGE__."::jsonLoad() must have 'path' argument, or be a 'Findable' and have a 'findable' argument" );
	}

	# load the raw JSON data
	if( $self->{_jsonable}{loadable} ){
		my $result = undef;
		$result = $self->jsonRead( $self->{_jsonable}{json} );
		if( defined( $result )){
			$self->{_jsonable}{loaded} = true;
			$self->{_jsonable}{raw} = $result;
		}

		# initialize the evaluated part, even if not actually evaluated, so that jsonData()
		# can at least returns raw - unevaluated - data
		$self->{_jsonable}{evaluated} = $self->{_jsonable}{raw};
	}
	
	return $self->jsonLoaded();
}

# -------------------------------------------------------------------------------------------------
# Getter/Setter
# Says if the JSON raw data has been successfully loaded
# (I]:
# - optional boolean to set the 'loaded' status
# (O):
# - true|false

sub jsonLoaded {
	my ( $self, $loaded ) = @_;

	$self->{_jsonable}{loaded} = $loaded if defined $loaded;

	return $self->{_jsonable}{loaded};
}

# -------------------------------------------------------------------------------------------------
# Returns the full path to the JSON file
# (I):
# - none
# (O):
# returns the path

sub jsonPath {
	my ( $self ) = @_;

	return $self->{_jsonable}{json};
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
# JSONable initialization
# Initialization of a command or of an external script
# (I):
# - the TTP EntryPoint ref
# (O):
# -none

after _newBase => sub {
	my ( $self, $ttp ) = @_;

	$self->{_jsonable} //= {};
	$self->{_jsonable}{loadable} = false;
	$self->{_jsonable}{json} = undef;
	$self->{_jsonable}{loaded} = false;
};

### Global functions

1;

__END__
