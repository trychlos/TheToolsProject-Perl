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
# Find a file

package TTP::Findable;
our $VERSION = '1.00';

use strict;
use warnings;

use Config;
use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

### Private methods

### Public methods
### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Returns the list of files which match the given specification by walking through TTP_ROOTS
# Honors TTP::Acceptable role for each candidate.
# (I]:
# - an argument object with following keys:
#   > patterns: the specifications to be searched for in TTP_ROOTS tree
#     as a scalar, or as a ref to an array of items which have to be concatenated,
#     when each item for the array may itself be an array of scalars to be sucessively tested
#   > wantsAll: whether we want a full list of just the first found
#     defaulting to true (wants the full list)
# - an optional options hash which will be passed to Acceptable role if the object implements it
# (O):
# - if 'wantsAll' is true, returns a ref to an array of (accepted) found files, which may be empty
# - if 'wantsAll' is false, returns a single scalar string which is the (accepted) found files, which may be undef

sub find {
	my ( $self, $args, $opts ) = @_;
	$opts //= {};
	my $result = undef;
	# check the provided arguments for type and emptyness
	my $ref = ref( $args );
	if( $ref eq 'HASH' ){
		if( $args->{patterns} ){
			$ref = ref( $args->{patterns} );
			if( $ref && $ref ne 'ARRAY' ){
				msgErr( __PACKAGE__."::_find() expects args->patterns be a scalar or an array, found '$ref'" );
			} else {
				$result = $self->_find_run( $args, $opts );
			}
		} else {
			msgErr( __PACKAGE__."::_find() expects args->patterns object, which has not been found" );
		}
	} else {
		msgErr( __PACKAGE__."::_find() expects args be a hash, found '$ref'" );
	}
	return $result;
}

# arguments have been checked, just run

sub _find_run {
	my ( $self, $args, $opts ) = @_;
	my $result = undef;
	# keep the passed-in arguments
	$self->{_findable}{args} = \%{$args};
	# initialize the results
	# we keep a track of each explored directory, or each candidate files and of its status
	$self->{_findable}{end} = false;
	$self->{_findable}{patterns} = [];
	$self->{_findable}{candidates} = [];
	$self->{_findable}{accepted} = [];
	$self->{_findable}{wantsAll} = true;
	$self->{_findable}{wantsAll} = $args->{wantsAll} if exists $args->{wantsAll};
	# iter on each root path
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	foreach my $it ( @roots ){
		$self->_find_inpath_rec( $args, $opts, $args->{patterns}, $it ) if !$self->{_findable}{end};
	}
	if( $self->{_findable}{wantsAll} ){
		$result = $self->{_findable}{accepted};
		msgVerbose( __PACKAGE__."::_find() returning [".join( ',', @{$result} )."]" );
	} else {
		$result = $self->{_findable}{accepted}->[0] if scalar @{$self->{_findable}{accepted}};
		msgVerbose( __PACKAGE__."::_find() returning '".( $result ? $result : '(undef)' )."'" );
	}
	return $result;
}

# is the current candidate file accepted by the caller
sub _find_accepted {
	my ( $self, $args, $candidate ) = @_;
	my $cb = undef;
	$cb = $args->{accept} if exists $args->{accept};
	my $accepted = defined( $cb ) ? $cb->( $candidate ) : true;
	msgVerbose( __PACKAGE__."::_find_accepted() candidate '$candidate' is refused" ) if !$accepted;
	return $accepted;
}

# search for the patterns in the specified path
# the provided findable patterns contains either a scalar or an array
# each item maybe a scalar (a single file specification), or an array of scalars (specs must be concatened), or an array of arrays of scalars (intermediary array scalars must be tested)

sub _find_inpath_rec {
	my ( $self, $args, $opts, $patterns, $rootDir ) = @_;
	my $ref = ref( $patterns );
	if( $ref ){
		if( $ref eq 'ARRAY' ){
			my $haveArray = false;
			LOOP: for( my $i=0 ; $i<scalar @{$patterns} ; ++$i ){
				$ref = ref( $patterns->[$i] );
				if( $ref && $ref ne 'ARRAY' ){
					msgErr( __PACKAGE__."::_find_inpath_rec() unexpected intermediate ref='$ref'" );
				# if an element of the patterns is itself an array, then each item of this later array must be tested
				} elsif( $ref ){
					$haveArray = true;
					my @newPatterns = @{$patterns};
					for( my $j=0 ; $j<scalar @{$patterns->[$i]} ; ++$j ){
						$newPatterns[$i] = $patterns->[$i][$j];
						$self->_find_inpath_rec( $args, $opts, \@newPatterns, $rootDir );
						last LOOP if $self->{_findable}{end};
					}
				}
			}
			# each part of the specs is a scalar, so just test that
			if( !$haveArray ){
				$self->_find_single( $args, $opts, File::Spec->catfile( $rootDir, @{$patterns} ));
			}
		} else {
			msgErr( __PACKAGE__."::_find_inpath_rec() unexpected final ref='$ref'" );
		}
	} else {
		$self->_find_single( $args, $opts, File::Spec->catfile( $rootDir, $patterns ));
	}
}

# test here for each candidate file

sub _find_single {
	my ( $self, $args, $opts, $candidate ) = @_;
	print __PACKAGE__."::_find_single() testing '$candidate'".EOL;
	if( -r $candidate ){
		push( @{$self->{_findable}{candidates}}, $candidate );
		my $accepted = true;
		if( $self->does( 'TTP::Acceptable' ) && $opts->{acceptable} ){
			$accepted = $self->accept( $opts->{acceptable}, $candidate );
		}
		if( $accepted ){
			push( @{$self->{_findable}{accepted}}, $candidate );
			#$self->{_findable}{end} = true unless $self->{_findable}{wantsAll};
			print __PACKAGE__."::_find_inpath() candidate='$candidate' is accepted".EOL;
		}
	}
}

# search for the patterns in the specified path
# the provided finder contains a non-empty patterns array
# each item maybe a scalar (a single file specification), or an array of scalars (specs must be concatened), or an array of arrays of scalars (intermediary array scalars must be tested)

sub _find_inpath_rec2 {
	my ( $self, $path, $args, $specs ) = @_;
	my $result = undef;
	my $ref = '';#ref( $finder->{dirs} );
	if( $ref && $ref ne 'ARRAY' ){
		msgErr( __PACKAGE__."::_find_inpath_rec() unexpected final ref='$ref'" );
	} elsif( $ref eq 'ARRAY' ){
		my $haveArray = false;
		LOOP: for( my $i=0 ; $i<scalar @{$specs} ; ++$i ){
			$ref = ref( $specs->[$i] );
			if( $ref && $ref ne 'ARRAY' ){
				msgErr( __PACKAGE__."::_find_inpath_rec() unexpected intermediate ref='$ref'" );
			# if a part of specs is itself an array, then each item of this later array must be tested
			} elsif( $ref ){
				$haveArray = true;
				my @newSpecs = @{$specs};
				for( my $j=0 ; $j<scalar @{$specs->[$i]} ; ++$j ){
					$newSpecs[$i] = $specs->[$i][$j];
					$result = $self->_find_inpath_rec( $path, \@newSpecs, $args );
					last LOOP if $result;
				}
			}
		}
		# each part of the specs is a scalar, so just test that
		if( !$haveArray ){
			my $fname = File::Spec->catfile( $path, @{$specs} );
			msgVerbose( __PACKAGE__."::_find_inpath_rec() examining '$fname'" );
			#print __PACKAGE__."::_find_inpath_rec() examining '$fname'".EOL;
			if( -r $fname && $self->_find_accepted( $args, $fname )){
				$result = $fname;
			}
		}
	} else {
		$result = $specs;
	}
	msgVerbose( __PACKAGE__."::_find_inpath_rec() returning '".( $result ? $result : '(undef)' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Findable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_findable} //= {};
};

1;

__END__
