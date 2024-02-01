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
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - output: optional
# - mode: full-diff, defaulting to 'full'
# - dummy: true|false, defaulting to false
# return true|false
sub backupDatabase {
	my ( $parms ) = @_;
	my $result = false;
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Toops::msgOut( "backuping database '$dbms->{config}{host}\\$dbms->{instance}{name}\\$parms->{database}'" );
	Mods::Toops::msgErr( "Dbms::backupDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Toops::msgErr( "Dbms::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Toops::msgErr( "Dbms::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !Mods::Toops::errs()){
		if( !$parms->{output} ){
			$parms->{output} = Mods::Dbms::computeDefaultBackupFilename( $dbms, $parms );
		}
		Mods::Toops::msgOut( "to '$parms->{output}'" );
		$result = Mods::Dbms::toPackage( 'backupDatabase', $dbms, $parms );
	}
	if( $result ){
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the DBMS object passed to underlying packages
sub _buildDbms {
	my $TTPVars = Mods::Toops::TTPVars();
	my $config = Mods::Toops::getHostConfig();
	my $dbms = $TTPVars->{dbms};
	$dbms->{config} = $config;
	$dbms->{exitCode} = \$TTPVars->{run}{exit_code};
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
	my $rootdir = $config->{DBMSInstances}{$parms->{instance}}{backupPath};
	Mods::Toops::msgVerbose( "Dbms::computeDefaultBackupFilename() found rootDir='$rootdir'" );
	if( !$rootdir ){
		Mods::Toops::msgWarn( "Dbms::computeDefaultBackupFilename() instance='$parms->{instance}' backupPath is not specified, set to default temp directory" );
		$rootdir = Mods::Toops::getDefaultTempDir();
	}
	my $dir = File::Spec->catdir( $rootdir, localtime->strftime( '%y%m%d' ));
	Mods::Toops::makeDirExist( $dir );
	# compute the filename
	my $fname = $dbms->{config}{host}.'-'.$parms->{instance}.'-'.$parms->{database}.'-'.localtime->strftime( '%y%m%d' ).'-'.localtime->strftime( '%H%M%S' ).'-'.$mode.'.backup';
	$output = File::Spec->catdir( $dir, $fname );
	Mods::Toops::msgVerbose( "Dbms::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the databases
# the working-on instance has been set by checkInstanceOpt() function
sub getDatabaseTables {
	my ( $dbms, $database ) = @_;
	my $list = Mods::Dbms::toPackage( 'getDatabaseTables', $dbms, $database );
	return $list;
}

# -------------------------------------------------------------------------------------------------
# returns the list of instance live databases
# the working-on instance has been set by checkInstanceOpt() function
sub getLiveDatabases {
	my ( $dbms ) = @_;
	my $list = Mods::Dbms::toPackage( 'getLiveDatabases', $dbms );
	return $list;
}

# -------------------------------------------------------------------------------------------------
# list the instance live databases
# the working-on instance has been set by checkInstanceOpt() function
sub listDatabaseTables {
	my ( $database ) = @_;
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Toops::msgErr( "Dbms::listDatabaseTables() instance is mandatory, but is not specified" ) if !$dbms->{instance};
	Mods::Toops::msgErr( "Dbms::listDatabaseTables() database is mandatory, but is not specified" ) if !$database;
	if( !Mods::Toops::errs()){
		Mods::Toops::msgOut( "displaying tables in '$dbms->{config}{host}\\$dbms->{instance}{name}\\$database'..." );
		my $list = Mods::Dbms::getDatabaseTables( $dbms, $database );
		foreach my $it ( @{$list} ){
			print " $it".EOL;
		}
		Mods::Toops::msgOut( scalar @{$list}." found table(s)" );
	}
}

# -------------------------------------------------------------------------------------------------
# list the instance live databases
# the working-on instance has been set by checkInstanceOpt() function
sub listLiveDatabases {
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Toops::msgOut( "displaying databases in '$dbms->{config}{host}\\$dbms->{instance}{name}'..." );
	my $list = Mods::Dbms::getLiveDatabases( $dbms );
	foreach my $db ( @{$list} ){
		print " $db".EOL;
	}
	Mods::Toops::msgOut( scalar @{$list}." found live database(s)" );
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
	Mods::Toops::msgVerbose( "Dbms::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
	my $package = $dbms->{config}{DBMSInstances}{$dbms->{instance}{name}}{package};
	my $result = undef;
	if( $package ){
		Module::Load::load( $package );
		if( $package->can( $fname )){
			$result = $package->$fname( $dbms, $parms );
		}
	} else {
		Mods::Toops::msgErr( "unable to find a package to address '$dbms->{instance}{name}' instance" );
	}
	Mods::Toops::msgVerbose( "Dbms::toPackage() returning with result='".( $result || '(undef)' )."'" );
	return $result;
}

1;
