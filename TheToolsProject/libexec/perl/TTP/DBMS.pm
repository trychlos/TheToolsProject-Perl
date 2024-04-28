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

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;
#use TTP::SqlServer;

### Private methods

### Public methods

# -------------------------------------------------------------------------------------------------
# Backup a database
# (I):
# - parms is a hash ref with following keys:
#   > database: mandatory
#   > output: optional
#   > mode: full-diff, defaulting to 'full'
#   > compress: true|false
# return a hash reference with:
# - status: true|false
# - output: the output filename (even if provided on input)

sub backupDatabase {
	my ( $self, $parms ) = @_;
	my $result = { status => false };
	msgErr( __PACKAGE__."::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( __PACKAGE__."::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !TTP::errs()){
		if( !$parms->{output} ){
			$parms->{output} = $self->computeDefaultBackupFilename( $parms );
		}
		msgOut( "backuping to '$parms->{output}'" );
		my $res = $self->toPackage( 'apiBackupDatabase', $parms );
		$result->{status} = $res->{ok};
	}
	$result->{output} = $parms->{output};
	if( !$result->{status} ){
		msgErr( __PACKAGE__."::backupDatabase() ".$self->instance()."\\$parms->{database} NOT OK" );
	} else {
		msgVerbose( __PACKAGE__."::backupDatabase() returning status='true' output='$result->{output}'" );
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/intance/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date part
# (I):
# - dbms, the DBMS object from _buildDbms()
# - parms is a hash ref with keys:
#   > database name: mandatory
#   > mode: defaulting to 'full'
# (O):
# - the default output full filename

sub computeDefaultBackupFilename {
	my ( $self, $parms ) = @_;
	#msgVerbose( __PACKAGE__."::computeDefaultBackupFilename() entering" );
	my $output = undef;
	msgErr( __PACKAGE__."::computeDefaultBackupFilename() database is mandatory, but is not specified" ) if !$parms->{database};
	my $mode = 'full';
	$mode = $parms->{mode} if exists $parms->{mode};
	msgErr( __PACKAGE__."::computeDefaultBackupFilename() mode must be 'full' or 'diff', found '$mode'" ) if $mode ne 'full' and $mode ne 'diff';
	# compute the dir and make sure it exists
	my $node = $self->ttp()->node();
	my $backupDir = $node->var([ 'DBMS', 'backupsDir' ]) || $node->var([ 'DBMS', 'backupsRoot' ]) || TTP::tempDir();;
	TTP::Path::makeDirExist( $backupDir );
	# compute the filename
	my $fname = $node->name().'-'.$self->instance()."-$parms->{database}-".localtime->strftime( '%y%m%d' ).'-'.localtime->strftime( '%H%M%S' ).'-'.$mode.'.backup';
	$output = File::Spec->catdir( $backupDir, $fname );
	msgVerbose( __PACKAGE__."::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

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
# Display a variable starting with its reference
# expects a data variable (not a reference to code, or so)
# a SqlResult is just an array of hashes, or an array of array of hashes in the case of a multiple
# result sets

sub displayTabularSql {
	my ( $self, $result ) = @_;
	my $ref = ref( $result );
	# expects an array, else just give up
	if( $ref ne 'ARRAY' ){
		msgVerbose( __PACKAGE__."::displayTabularSql() expected an array, but found '$ref', so just give up" );
		return;
	}
	if( !scalar @{$result} ){
		msgVerbose( __PACKAGE__."::displayTabularSql() got an empty array, so just give up" );
		return;
	}
	# expects an array of hashes
	# if we got an array of arrays, then this is a multiple result sets and recurse
	$ref = ref( $result->[0] );
	if( $ref eq 'ARRAY' ){
		foreach my $set ( @{$result} ){
			$self->displayTabularSql( $set );
		}
		return;
	}
	if( $ref ne 'HASH' ){
		msgVerbose( __PACKAGE__."::displayTabularSql() expected an array of hashes, but found an array of '$ref', so just give up" );
		return;
	}
	# first compute the max length of each field name + keep the same field order
	my $lengths = {};
	my @fields = ();
	foreach my $key ( keys %{@{$result}[0]} ){
		push( @fields, $key );
		$lengths->{$key} = length $key;
	}
	# and for each field, compute the max length content
	my $haveWarned = false;
	foreach my $it ( @{$result} ){
		foreach my $key ( keys %{$it} ){
			if( $lengths->{$key} ){
				if( defined $it->{$key} && length $it->{$key} > $lengths->{$key} ){
					$lengths->{$key} = length $it->{$key};
				}
			} elsif( !$haveWarned ){
				msgWarn( "found a row with different result set, do you have omit '--multiple' option ?" );
				$haveWarned = true;
			}
		}
	}
	# and last display the full resulting array
	# have a carriage return to be aligned on line beginning in log files
	foreach my $key ( @fields ){
		print TTP::pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $key ( @fields ){
		print TTP::pad( "| $key", $lengths->{$key}+3, ' ' );
	}
	print "|".EOL;
	foreach my $key ( @fields ){
		print TTP::pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $it ( @{$result} ){
		foreach my $key ( @fields ){
			print TTP::pad( "| ".( defined $it->{$key} ? $it->{$key} : "" ), $lengths->{$key}+3, ' ' );
		}
		print "|".EOL;
	}
	foreach my $key ( @fields ){
		print TTP::pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
}

# -------------------------------------------------------------------------------------------------
# execute a sql command
# (I):
# - the command string to be executed
# - an optional options hash which may contain following keys:
#   > tabular: whether to format data as tabular data, defaulting to true
#   > multiple: whether we expect several result sets, defaulting to false
# (O):
# returns a hash ref with following keys:
# - ok: true|false
# - result: an array ref to hash results

sub execSqlCommand {
	my ( $self, $command, $opts ) = @_;
	$opts //= {};
	my $parms = {
		command => $command,
		opts => $opts
	};
	my $result = $self->toPackage( 'apiExecSqlCommand', $parms );
	if( $result && $result->{ok} ){
		my $tabular = true;
		$tabular = $opts->{tabular} if exists $opts->{tabular};
		if( $tabular ){
			$self->displayTabularSql( $result->{result} );
		} else {
			msgVerbose( "do not display tabular result as opts->{tabular}='false'" );
		}
	}
	return $result;
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

# ------------------------------------------------------------------------------------------------
# Restore a file into a database
# (I):
# - parms is a hash ref with keys:
#   > database: mandatory
#   > full: mandatory, the full backup file
#   > diff: optional, the diff backup file
#   > verifyonly: whether we want only check the restorability of the provided file
# (O):
# - return true|false

sub restoreDatabase {
	my ( $self, $parms ) = @_;
	my $result = undef;
	msgErr( __PACKAGE__."::restoreDatabase() database is mandatory, but is not specified" ) if !$parms->{database} && !$parms->{verifyonly};
	msgErr( __PACKAGE__."::restoreDatabase() full backup is mandatory, but is not specified" ) if !$parms->{full};
	msgErr( __PACKAGE__."::restoreDatabase() $parms->{diff}: file not found or not readable" ) if $parms->{diff} && ! -f $parms->{diff};
	if( !TTP::errs()){
		$result = $self->toPackage( 'apiRestoreDatabase', $parms );
	}
	if( $result && $result->{ok} ){
		msgVerbose( __PACKAGE__."::restoreDatabase() returning status='true'" );
	} else {
		msgErr( __PACKAGE__."::restoreDatabase() ".$self->instance()."\\$parms->{database} NOT OK" );
	}
	return $result && $result->{ok};
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
