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
# Manage the site configuration as a site context

package TTP::Site;

use base qw( TTP::JSONable );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# allowed top keys in the site configuration file
	# either exact keys or anything which ends with 'comments'
	keys => [
		'comments$',
		'^site$',
		'^toops$',
		'^TTP$'
	],
	# hardcoded subpath to find the global site.json
	# even if this not too sexy in Win32, this is a standard and a common usage on Unix/Darwin platforms
	site => [
		'etc/ttp/site.json',
		'etc/site.json',
		'etc/ttp/toops.json',
		'etc/toops.json'
	]
};

### Private methods

# -------------------------------------------------------------------------------------------------
# Check the top keys of the provided hash, making sure only allowed keys are here
# (I):
# - hash ref to be checked
# - array ref of allowed keys
# (O):
# - a ref to the array of unallowed keys

sub _checkTopKeys {
	my ( $self, $hash, $allowedKeys ) = @_;
	my $others = [];
	foreach my $key ( keys %{$hash} ){
		#my $allowed = grep( /key/, @{$allowedKeys} );
		my $allowed = false;
		foreach my $it ( @{$allowedKeys} ){
			$allowed = ( $key =~ m/$it/ ) if !$allowed;
		}
		push( @{$others}, $key ) if !$allowed;
	}
	return $others;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Returns the disallowed keys found in the site configuration file
# (I]:
# - none
# (O):
# - disallowed keys as an array ref, maybe empty

sub disallowed {
	my ( $self, $args ) = @_;
	return $self->{_disallowed};
}

# -------------------------------------------------------------------------------------------------
# Says if the site configuration has been successfully loaded, evaluated and checked
# Not the same as JSONable->loaded() because this later only says if raw data has been successfully loaded 
# (I]:
# - none
# (O):
# - true|false

sub success {
	my ( $self, $args ) = @_;
	return $self->{_success};
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};

	# set the site ending path list before trying to load and evaluate the JSON configuration file
	#  specs here is a ref to an array of arrays which have to be successively tested
	$args->{spec} = [ $Const->{site} ];
	my $self = $class->SUPER::new( $args );
	bless $self, $class;

	# unable to find and load a site configuration file ? this is an unrecoverable error
	if( !$self->SUPER::success()){
		msgErr( "Unable to find the site configuration file among [".( join( ',', @{TTP::Site->spec()}))."]" );
		msgErr( "Please make sure that the file exists in one of the TTP_ROOTS paths" );
		msgErr( "Exiting with code 1" );
		exit( 1 );
	}

	# check the top keys of the site file
	# found a not allowed key ? this is still an unrecoverable error
	$self->{_success} = false;
	$self->{_disallowed} = [];
	if( $self->TTP::JSONable::success()){
		$self->{_disallowed} = $self->_checkTopKeys( $self->get(), $Const->{keys } );
		if( scalar @{$self->{_disallowed}} ){
			msgErr( "Invalid key(s) found in site configuration file: [".join( ', ', @{$self->disallowed()} )."]" );
			msgErr( "Remind that site own keys should be inside 'site' hierarchy while TTP global configuration must be inside 'toops' hierarchy" );
			msgErr( "Exiting with code 1" );
			exit( 1 );
		} else {
			$self->{_success} = true;
		}
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Class method
# (I]:
# - none
# (O):
# - Returns the Const->{site} specification as an array ref

sub spec {
	my ( $class, $args ) = @_;
	$class = ref( $class ) || $class;
	return $Const->{site};
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
