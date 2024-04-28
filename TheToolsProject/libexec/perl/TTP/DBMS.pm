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
# An indirection level between the verb scripts and the underlying product-specialized packages
#(Win32::SqlServer, PostgreSQL and MariaDB are involved)

package TTP::DBMS;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Data::Dumper;
use File::Path;
use File::Spec;
use Module::Load;
use Time::Piece;
use vars::global qw( $ttp );

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;
#use TTP::SqlServer;

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# check that the specified database exists in the instance
# (I):
# - the database name
# (O):
# returns true|false

sub databaseExists {
	my ( $self, $database ) = @_;
	my $exists = false;

	if( $database ){
		my $list = $self->getDatabases();
		$exists = true if grep( /$database/i, @{$list} );
	} else {
		msgErr( __PACKAGE__."::databaseExists() database is mandatory, but is not specified" );
	}

	msgVerbose( "checkDatabaseExists() returning ".( $exists ? 'true' : 'false' ));
	return $exists;
}

# -------------------------------------------------------------------------------------------------
# returns the list of instance databases
# (I):
# - none
# (O):
# - the list of databases in the instance as an array ref, ay be empty

sub getDatabases {
	my ( $self ) = @_;

	my $result = $self->toPackage( 'apiGetInstanceDatabases' );

	return $result->{output} || [];
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the databases
# (I):
# - the database to list the tables from
# (O):
# - the list of tables in the database as an array ref, ay be empty

sub getDatabaseTables {
	my ( $self, $database ) = @_;

	my $result = $self->toPackage( 'apiGetDatabaseTables', { database => $database });

	return $result->{output} || [];
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# returns the instance name

sub instance {
	my ( $self ) = @_;

	return $self->{_dbms}{instance};
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# returns the name of the package which manages this instance type

sub package {
	my ( $self ) = @_;

	return $self->{_dbms}{package};
}

# -------------------------------------------------------------------------------------------------
# address a function in the package which deserves the instance
#  and returns the result which is expected to be a hash with (at least) a 'ok' key, or undef
# (I):
# - the name of the function to be called
# - an optional options hash to be passed to the function
# (O):
# - the result

sub toPackage {
	my ( $self, $fname, $parms ) = @_;
	msgVerbose( __PACKAGE__."::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
	my $result = undef;
	if( $fname ){
		my $package = $self->package();
		Module::Load::load( $package );
		if( $package->can( $fname )){
			$result = $package->$fname( $self, $parms );
		} else {
			msgWarn( __PACKAGE__."::toPackage() package '$package' says it cannot '$fname'" );
		}
	} else {
		msgErr( __PACKAGE__."::toPackage() function name must be specified" );
	}
	msgVerbose( __PACKAGE__."::toPackage() returning with result='".( defined $result ? ( $result->{ok} ? 'true':'false' ) : '(undef)' )."'" );
	return $result;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > instance: the instance name
# (O):
# - this object, or undef in case of an error

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp, $args );
	bless $self, $class;

	if( $args->{instance} ){
		$self->{_dbms}{instance} = $args->{instance};
		my $package = $ttp->var([ 'DBMS', 'byInstance', $args->{instance}, 'package' ]);
		#print __PACKAGE__."::var() package='".( $package || '(undef)' )."'".EOL;
		if( $package ){
			$self->{_dbms}{package} = $package;
			msgVerbose( __PACKAGE__."::new() package='$package'" );
		} else {
			msgErr( __PACKAGE__."::new() unable to find a suitable package for '$args->{instance}' instance" );
			$self = undef;
		}

	} else {
		msgErr( __PACKAGE__."::new() instance is mandatory, but is not specified" );
		$self = undef;
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
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

1;

__END__
