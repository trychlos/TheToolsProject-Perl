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
# Find the first file which matches the given specification by walking through TTP_ROOTS
# (I]:
# - an argument object with following keys:
#   > spec: the specification to be searched for in TTP_ROOTS tree
#     as a scalar, or as a ref to an array of items which have to be concatenated,
#     when each item for the array may itself be an array of scalars to be sucessively tested
#   > accept: a code reference which will receive the full path of the candidate, and must return
#     true|false to accept or refuse this file
#     defaults to true if accept is not specified
# (O):
# - the full pathname of a found and accepted file

sub find {
	my ( $self, $args ) = @_;
	my $result = undef;
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $specs = $args->{spec};
	$specs = [ $args->{spec} ] if !ref( $args->{spec} );
	foreach my $it ( @roots ){
		$result = $self->_find_inpath_rec( $it, $specs, $args );
		last if $result;
	}
	msgVerbose( __PACKAGE__."::_find() returning '".( $result ? $result : '(undef)' )."'" );
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

# search for the specs in the specified path
# specs maybe a scalar (a single file specification), or an array of scalars (specs must be concatened), or an array of arrays of scalars (intermediary array scalars must be tested)
sub _find_inpath_rec {
	my ( $self, $path, $specs, $args ) = @_;
	my $result = undef;
	my $ref = ref( $specs );
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
