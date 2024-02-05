# Copyright (@) 2023-2024 PWI Consulting
#
# An indirection level between the verb scripts and the underlying product-specialized packages (Win32::SqlServer, PostgreSQL and MariaDB are involved)

package Mods::Dbms;

use strict;
use warnings;

use Data::Dumper;
use File::Path;
use File::Spec;
use Module::Load;
#use Module::Runtime;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - output: optional
# - mode: full-diff, defaulting to 'full'
# return a hash reference with:
# - status: true|false
# - output: the output filename (even if provided on input)
sub backupDatabase {
	my ( $parms ) = @_;
	my $result = { status => false };
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Toops::msgErr( "Dbms::backupDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Toops::msgErr( "Dbms::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Toops::msgErr( "Dbms::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !Mods::Toops::errs()){
		if( !$parms->{output} ){
			$parms->{output} = Mods::Dbms::computeDefaultBackupFilename( $dbms, $parms );
		}
		Mods::Toops::msgOut( "backuping to '$parms->{output}'" );
		$result->{status} = Mods::Dbms::toPackage( 'apiBackupDatabase', $dbms, $parms );
	}
	$result->{output} = $parms->{output};
	Mods::Toops::msgVerbose( "Dbms::backupDatabase() returning $result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the DBMS object passed to underlying packages
# which gives dbms:
# - config
#   > DBMSInstances
#   > ...
# - instance
#   > name
#   > data -> $hostConfig->{DBMSInstances}{<name>}
# - \exitCode
sub _buildDbms {
	my $TTPVars = Mods::Toops::TTPVars();
	my $dbms = $TTPVars->{dbms};
	$dbms->{config} = Mods::Toops::getHostConfig();
	$dbms->{exitCode} = \$TTPVars->{run}{exitCode};
	return $dbms;
}

# -------------------------------------------------------------------------------------------------
# check that the specified database exists in the specified instance
# returns true|false
sub checkDatabaseExists {
	my ( $instance, $database ) = @_;
	my $exists = false;
	Mods::Toops::msgVerbose( "Dbms::checkDatabaseExists() entering with instance='".( $instance || '(undef)' )."', database='".( $database || '(undef)' )."'" );
	Mods::Toops::msgErr( "Dbms::checkDatabaseExists() instance is mandatory, but is not specified" ) if !$instance;
	Mods::Toops::msgErr( "Dbms::checkDatabaseExists() database is mandatory, but is not specified" ) if !$database;
	if( !Mods::Toops::errs()){
		my $dbms = Mods::Dbms::_buildDbms();
		my $list = Mods::Dbms::getLiveDatabases( $dbms );
		$exists = true if grep( /$database/, @{$list} );
	}
	Mods::Toops::msgVerbose( "checkDatabaseExists() returning ".( $exists ? 'true' : 'false' ));
	return $exists;
}

# -------------------------------------------------------------------------------------------------
# check that the provided instance name is valid on this machine
# - may be none if there is one and only one instance on the machine (though this emit a warning about future evolutions)
# - must be referenced in the json configuration file for the host
# (E):
# - the candidate instance name
# - options, which may have:
#   > mandatory: true|false, defaulting to true
#   > single: true|false, whether to search for a single defined instance if none is provided, defaulting to true
# returns the found and checked instance, or undef in case of an error
# if found, set up instance -> { name, data } in TTPVars
sub checkInstanceOpt {
	my ( $name, $opts ) = @_;
	$opts //= {};
	Mods::Toops::msgVerbose( "Dbms::checkInstanceOpt() entering with name='".( $name || '(undef)' )."'" );
	my $config = Mods::Toops::getHostConfig();
	my $instance = undef;
	if( $config->{DBMSInstances} ){
		if( $name ){
			if( exists( $config->{DBMSInstances}{$name} )){
				Mods::Toops::msgVerbose( "found instance='$name'" );
				$instance = $name;
			} else {
				Mods::Toops::msgErr( "Dbms::checkInstanceOpt() instance '$name' not defined in host configuration" );
			}
		} else {
			my $single = true;
			$single = $opts->{single} if exists $opts->{single};
			if( $single ){
				my $count = scalar keys( %{$config->{DBMSInstances}} );
				if( $count == 1 ){
					$instance = ( keys %{$config->{DBMSInstances}} )[0];
					Mods::Toops::msgVerbose( "Dbms::checkInstanceOpt() '--instance' option not specified, executing on lonely defined '$instance'" );
					Mods::Toops::msgWarn( "you are relying on a single instance definition; be warned that this facility may change in the future" );
				} else {
					my $mandatory = true;
					$mandatory = $opts->{mandatory} if exists $opts->{mandatory};
					if( $mandatory ){
						Mods::Toops::msgErr( "'--instance' option is mandatory, none found (and there is none or too many DBMS instances)" );
					} else {
						Mods::Toops::msgVerbose( "'--instance' option is optional, has not been specified" );
					}
				}
			} else {
				Mods::Toops::msgVerbose( "'--instance' option is not specified, and 'single' is false, returning none" );
			}
		}
	} else {
		Mods::Toops::msgErr( "no 'DBMSInstances' key defined in host configuration" );
	}
	if( $instance ){
		my $TTPVars = Mods::Toops::TTPVars();
		$TTPVars->{dbms}{instance} = {
			name => $instance,
			data => $config->{DBMSInstances}{$instance}
		};
	}
	Mods::Toops::msgVerbose( "Dbms::checkInstanceOpt() returning with instance='".( $instance || '(undef)' )."'" );
	return $instance;
}

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/intance/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupPath is expected to be daily-ised, ie to contain a date part
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - mode: defaulting to 'full'
sub computeDefaultBackupFilename {
	my ( $dbms, $parms ) = @_;
	Mods::Toops::msgVerbose( "Dbms::computeDefaultBackupFilename() entering" );
	my $output = undef;
	my $config = Mods::Toops::getHostConfig();
	Mods::Toops::msgErr( "Dbms::computeDefaultBackupFilename() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Toops::msgErr( "Dbms::computeDefaultBackupFilename() instance is specified, but is not defined in host configuration" ) if !exists $config->{DBMSInstances}{$parms->{instance}};
	Mods::Toops::msgErr( "Dbms::computeDefaultBackupFilename() database is mandatory, but is not specified" ) if !$parms->{database};
	my $mode = 'full';
	$mode = $parms->{mode} if exists $parms->{mode};
	Mods::Toops::msgErr( "Dbms::computeDefaultBackupFilename() mode must be 'full' or 'diff', found '$mode'" ) if $mode ne 'full' and $mode ne 'diff';
	# compute the dir and make sure it exists
	my $backupPath = $config->{backupPath};
	Mods::Toops::msgVerbose( "Dbms::computeDefaultBackupFilename() found backupPath='$backupPath'" );
	if( !$backupPath ){
		Mods::Toops::msgWarn( "Dbms::computeDefaultBackupFilename() instance='$parms->{instance}' backupPath is not specified, set to default temp directory" );
		$backupPath = Mods::Toops::getDefaultTempDir();
	}
	Mods::Toops::makeDirExist( $backupPath );
	# compute the filename
	my $fname = $dbms->{config}{name}.'-'.$parms->{instance}.'-'.$parms->{database}.'-'.localtime->strftime( '%y%m%d' ).'-'.localtime->strftime( '%H%M%S' ).'-'.$mode.'.backup';
	$output = File::Spec->catdir( $backupPath, $fname );
	Mods::Toops::msgVerbose( "Dbms::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# -------------------------------------------------------------------------------------------------
# Display a variable starting with its reference
# expects a data variable (not a reference to code, or so)
# a SqlResult is just an array of hashes
sub displayTabularSql {
	my ( $ref ) = @_;
	# first compute the max length of each field name + keep the same field order
	my $lengths = {};
	my @fields = ();
	foreach my $key ( keys %{@{$ref}[0]} ){
		push( @fields, $key );
		$lengths->{$key} = length $key;
	}
	# and for each field, compute the max length content
	foreach my $it ( @{$ref} ){
		foreach my $key ( keys %{$it} ){
			if( $it->{$key} && length $it->{$key} > $lengths->{$key} ){
				$lengths->{$key} = length $it->{$key};
			}
		}
	}
	# and last display the full resulting array
	# have a carriage return to be aligned on line beginning in log files
	print EOL;
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $key ( @fields ){
		print pad( "| $key", $lengths->{$key}+3, ' ' );
	}
	print "|".EOL;
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
	foreach my $it ( @{$ref} ){
		foreach my $key ( @fields ){
			print pad( "| ".( $it->{$key} || "" ), $lengths->{$key}+3, ' ' );
		}
		print "|".EOL;
	}
	foreach my $key ( @fields ){
		print pad( "+", $lengths->{$key}+3, '-' );
	}
	print "+".EOL;
}

# -------------------------------------------------------------------------------------------------
# execute a sql command
# (E):
# - the command string to be executed
# - an optional options hash which may contain following keys:
#   > tabular: whether to format data as tabular data, defaulting to true
sub execSqlCommand {
	my ( $command, $opts ) = @_;
	$opts //= {};
	my $dbms = Mods::Dbms::_buildDbms();
	my $result = Mods::Dbms::toPackage( 'apiExecSqlCommand', $dbms, $command );
	my $tabular = true;
	$tabular = $opts->{tabular} if exists $opts->{tabular};
	displayTabularSql( $result ) if $tabular;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the databases
# the working-on instance has been set by checkInstanceOpt() function
sub getDatabaseTables {
	my ( $database ) = @_;
	my $list = Mods::Dbms::toPackage( 'apiGetDatabaseTables', undef, $database );
	return $list;
}

# -------------------------------------------------------------------------------------------------
# returns the list of instance live databases
# the working-on instance has been set by checkInstanceOpt() function
sub getLiveDatabases {
	my ( $dbms ) = @_;
	my $list = Mods::Dbms::toPackage( 'apiGetInstanceDatabases', $dbms );
	return $list;
}

# -------------------------------------------------------------------------------------------------
# pad the provided string until the specified length
sub pad {
	my( $str, $length, $pad ) = @_;
	return Mods::Toops::pad( $str, $length, $pad );
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - full: mandatory, the full backup file
# - diff: optional, the diff backup file
# - verifyonly: whether we want only check the restorability of the provided file
# return true|false
sub restoreDatabase {
	my ( $parms ) = @_;
	my $result = false;
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Toops::msgErr( "Dbms::restoreDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Toops::msgErr( "Dbms::restoreDatabase() database is mandatory, but is not specified" ) if !$parms->{database} && !$parms->{verifyonly};
	Mods::Toops::msgErr( "Dbms::restoreDatabase() full backup is mandatory, but is not specified" ) if !$parms->{full};
	Mods::Toops::msgErr( "Dbms::restoreDatabase() $parms->{diff}: file not found or not readable" ) if $parms->{diff} && ! -f $parms->{diff};
	if( !Mods::Toops::errs()){
		$result = Mods::Dbms::toPackage( 'apiRestoreDatabase', $dbms, $parms );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# check that the provided instance name is valid on this machine
# - may be none if there is one and only one instance on the machine (though this emit a warning about future evolutions)
# - must be referenced in the json configuration file for the host
# opts may have:
# - mandatory: true|false, defaulting to true
# returns the found and checked instance, or undef in case of an error
sub setInstanceByName {
	my $name = shift;
	Mods::Toops::msgVerbose( "Dbms::setInstanceByName() entering with name='".( $name || '(undef)' )."'" );
	my $config = Mods::Toops::getHostConfig();
	my $instance = undef;
	if( $config->{DBMSInstances} && $name && exists( $config->{DBMSInstances}{$name} )){
		$instance = $name;
		my $TTPVars = Mods::Toops::TTPVars();
		$TTPVars->{dbms}{instance} = {
			name => $name,
			data => $config->{DBMSInstances}{$name}
		};
	} else {
		Mods::Toops::msgErr( "no 'DBMSInstances' key, or name is undefined or is not defined in host configuration" );
	}
	Mods::Toops::msgVerbose( "Dbms::setInstanceByName() returning with found='".( $instance || '(undef)' )."'" );
	return $instance;
}

# -------------------------------------------------------------------------------------------------
# address a function in the package which deserves the named instance
#  and returns the result
sub toPackage {
	my ( $fname, $dbms, $parms ) = @_;
	my $result = undef;
	Mods::Toops::msgErr( "Dbms::toPackage() function name must be specified" ) if !$fname;
	if( !Mods::Toops::errs()){
		Mods::Toops::msgVerbose( "Dbms::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
		$dbms = Mods::Dbms::_buildDbms() if !$dbms;
		my $package = $dbms->{config}{DBMSInstances}{$dbms->{instance}{name}}{package};
		Mods::Toops::msgVerbose( "Dbms::toPackage() package='".( $package || '(undef)' )."'" );
		if( $package ){
			Module::Load::load( $package );
			#Module::Runtime::use_module( $package );
			if( $package->can( $fname )){
				$result = $package->$fname( $dbms, $parms );
			} else {
				Mods::Toops::msgWarn( "Dbms::toPackage() package '$package' says it cannot '$fname'" );
			}
		} else {
			Mods::Toops::msgErr( "unable to find a package to address '$dbms->{instance}{name}' instance" );
		}
		Mods::Toops::msgVerbose( "Dbms::toPackage() returning with result='".( $result || '(undef)' )."'" );
	}
	return $result;
}

1;
