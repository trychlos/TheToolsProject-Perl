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
use Mods::Path;
use Mods::Toops;
#use Mods::SqlServer;

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - output: optional
# - mode: full-diff, defaulting to 'full'
# - compress: true|false
# return a hash reference with:
# - status: true|false
# - output: the output filename (even if provided on input)
sub backupDatabase {
	my ( $parms ) = @_;
	my $result = { status => false };
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Message::msgErr( "Dbms::backupDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Message::msgErr( "Dbms::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Message::msgErr( "Dbms::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !Mods::Toops::errs()){
		if( !$parms->{output} ){
			$parms->{output} = Mods::Dbms::computeDefaultBackupFilename( $dbms, $parms );
		}
		Mods::Message::msgOut( "backuping to '$parms->{output}'" );
		my $res = Mods::Dbms::toPackage( 'apiBackupDatabase', $dbms, $parms );
		$result->{status} = $res->{ok};
	}
	$result->{output} = $parms->{output};
	if( !$result->{status} ){
		Mods::Message::msgErr( "Dbms::backupDatabase() $parms->{instance}\\$parms->{database} NOT OK" );
	} else {
		Mods::Message::msgVerbose( "Dbms::backupDatabase() returning status='true' output='$result->{output}'" );
	}
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
	Mods::Message::msgVerbose( "Dbms::checkDatabaseExists() entering with instance='".( $instance || '(undef)' )."', database='".( $database || '(undef)' )."'" );
	Mods::Message::msgErr( "Dbms::checkDatabaseExists() instance is mandatory, but is not specified" ) if !$instance;
	Mods::Message::msgErr( "Dbms::checkDatabaseExists() database is mandatory, but is not specified" ) if !$database;
	if( !Mods::Toops::errs()){
		my $dbms = Mods::Dbms::_buildDbms();
		my $list = Mods::Dbms::getLiveDatabases( $dbms );
		$exists = true if grep( /$database/i, @{$list} );
	}
	Mods::Message::msgVerbose( "checkDatabaseExists() returning ".( $exists ? 'true' : 'false' ));
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
	Mods::Message::msgVerbose( "Dbms::checkInstanceOpt() entering with name='".( $name || '(undef)' )."'" );
	my $config = Mods::Toops::getHostConfig();
	my $instance = undef;
	if( $config->{DBMSInstances} ){
		if( $name ){
			if( exists( $config->{DBMSInstances}{$name} )){
				Mods::Message::msgVerbose( "found instance='$name'" );
				$instance = $name;
			} else {
				Mods::Message::msgErr( "Dbms::checkInstanceOpt() instance '$name' not defined in host configuration" );
			}
		} else {
			my $single = true;
			$single = $opts->{single} if exists $opts->{single};
			if( $single ){
				my $count = scalar keys( %{$config->{DBMSInstances}} );
				if( $count == 1 ){
					$instance = ( keys %{$config->{DBMSInstances}} )[0];
					Mods::Message::msgVerbose( "Dbms::checkInstanceOpt() '--instance' option not specified, executing on lonely defined '$instance'" );
					Mods::Message::msgWarn( "you are relying on a single instance definition; be warned that this facility may change in the future" );
				} else {
					my $mandatory = true;
					$mandatory = $opts->{mandatory} if exists $opts->{mandatory};
					if( $mandatory ){
						Mods::Message::msgErr( "'--instance' option is mandatory, none found (and there is none or too many DBMS instances)" );
					} else {
						Mods::Message::msgVerbose( "'--instance' option is optional, has not been specified" );
					}
				}
			} else {
				Mods::Message::msgVerbose( "'--instance' option is not specified, and 'single' is false, returning none" );
			}
		}
	} else {
		Mods::Message::msgErr( "no 'DBMSInstances' key defined in host configuration" );
	}
	if( $instance ){
		my $TTPVars = Mods::Toops::TTPVars();
		$TTPVars->{dbms}{instance} = {
			name => $instance,
			data => $config->{DBMSInstances}{$instance}
		};
	}
	Mods::Message::msgVerbose( "Dbms::checkInstanceOpt() returning with instance='".( $instance || '(undef)' )."'" );
	return $instance;
}

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/intance/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date part
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - mode: defaulting to 'full'
sub computeDefaultBackupFilename {
	my ( $dbms, $parms ) = @_;
	Mods::Message::msgVerbose( "Dbms::computeDefaultBackupFilename() entering" );
	my $output = undef;
	my $config = Mods::Toops::getHostConfig();
	Mods::Message::msgErr( "Dbms::computeDefaultBackupFilename() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Message::msgErr( "Dbms::computeDefaultBackupFilename() instance is specified, but is not defined in host configuration" ) if !exists $config->{DBMSInstances}{$parms->{instance}};
	Mods::Message::msgErr( "Dbms::computeDefaultBackupFilename() database is mandatory, but is not specified" ) if !$parms->{database};
	my $mode = 'full';
	$mode = $parms->{mode} if exists $parms->{mode};
	Mods::Message::msgErr( "Dbms::computeDefaultBackupFilename() mode must be 'full' or 'diff', found '$mode'" ) if $mode ne 'full' and $mode ne 'diff';
	# compute the dir and make sure it exists
	my $backupDir = Mods::Path::dbmsBackupsDir();
	if( !$backupDir ){
		Mods::Message::msgWarn( "Dbms::computeDefaultBackupFilename() instance='$parms->{instance}' backupDir is not specified, set to default temp directory" );
		$backupDir = Mods::Toops::getDefaultTempDir();
	}
	# compute the filename
	my $fname = $dbms->{config}{name}.'-'.$parms->{instance}.'-'.$parms->{database}.'-'.localtime->strftime( '%y%m%d' ).'-'.localtime->strftime( '%H%M%S' ).'-'.$mode.'.backup';
	$output = File::Spec->catdir( $backupDir, $fname );
	Mods::Message::msgVerbose( "Dbms::computeDefaultBackupFilename() computing output default as '$output'" );
	return $output;
}

# -------------------------------------------------------------------------------------------------
# Display a variable starting with its reference
# expects a data variable (not a reference to code, or so)
# a SqlResult is just an array of hashes, or an array of array of hashes in the case of a multiple result sets
sub displayTabularSql {
	my ( $result ) = @_;
	my $ref = ref( $result );
	# expects an array, else just give up
	if( $ref ne 'ARRAY' ){
		Mods::Message::msgVerbose( "Dbms::displayTabularSql() expected an array, but found '$ref', so just give up" );
		return;
	}
	if( !scalar @{$result} ){
		Mods::Message::msgVerbose( "Dbms::displayTabularSql() got an empty array, so just give up" );
		return;
	}
	# expects an array of hashes
	# if we got an array of arrays, then this is a multiple result sets and recurse
	$ref = ref( $result->[0] );
	if( $ref eq 'ARRAY' ){
		foreach my $set ( @{$result} ){
			displayTabularSql( $set );
		}
		return;
	}
	if( $ref ne 'HASH' ){
		Mods::Message::msgVerbose( "Dbms::displayTabularSql() expected an array of hashes, but found an array of '$ref', so just give up" );
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
				if( $it->{$key} && length $it->{$key} > $lengths->{$key} ){
					$lengths->{$key} = length $it->{$key};
				}
			} elsif( !$haveWarned ){
				Mods::Message::msgWarn( "found a row with different result set, do you have omit '--multiple' option ?" );
				$haveWarned = true;
			}
		}
	}
	# and last display the full resulting array
	# have a carriage return to be aligned on line beginning in log files
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
	foreach my $it ( @{$result} ){
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
	my ( $command, $opts ) = @_;
	$opts //= {};
	my $dbms = Mods::Dbms::_buildDbms();
	my $parms = {
		command => $command,
		opts => $opts
	};
	my $result = Mods::Dbms::toPackage( 'apiExecSqlCommand', $dbms, $parms );
	if( $result && $result->{ok} ){
		my $tabular = true;
		$tabular = $opts->{tabular} if exists $opts->{tabular};
		if( $tabular ){
			displayTabularSql( $result->{result} );
		} else {
			Mods::Message::msgVerbose( "do not display tabular result as opts->{tabular}='false'" );
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the databases
# the working-on instance has been set by checkInstanceOpt() function
sub getDatabaseTables {
	my ( $database ) = @_;
	my $result = Mods::Dbms::toPackage( 'apiGetDatabaseTables', undef, $database );
	return $result->{output} || [];
}

# -------------------------------------------------------------------------------------------------
# returns the list of instance live databases
# the working-on instance has been set by checkInstanceOpt() function
sub getLiveDatabases {
	my ( $dbms ) = @_;
	my $result = Mods::Dbms::toPackage( 'apiGetInstanceDatabases', $dbms );
	return $result->{output} || [];
}

# -------------------------------------------------------------------------------------------------
# Converts back the output of displayTabularSql() function to an array of hashes
# as the only way for an external command to get the output of a sql batch is to pass through a tabular display output and re-interpretation
# (I):
# - an array of the lines outputed by a 'dbms.pl sql -tabular' command, which may contains several result sets
#   it is expected the output has already be filtered through Toops::ttpFilter()
# (O):
# returns:
# - an array of hashes if we have found a single result set
# - an array of arrays of hashes if we have found several result sets
sub hashFromTabular {
	my ( $output ) = @_;
	my $result = [];
	my $multiple = false;
	my $array = [];
	my $sepCount = 0;
	my @columns = ();
	foreach my $line ( @{$output} ){
		if( $line =~ /^\+---/ ){
			$sepCount += 1;
			next;
		}
		# found another result set
		if( $sepCount == 4 ){
			$multiple = true;
			push( @{$result}, $array );
			$array = [];
			@columns = ();
			$sepCount = 1;
		}
		# header line -> provide column names
		if( $sepCount == 1 ){
			@columns = split( /\s*\|\s*/, $line );
			shift @columns;
		}
		# get data
		if( $sepCount == 2 ){
			my @data = split( /\s*\|\s*/, $line );
			shift @data;
			my $row = {};
			for( my $i=0 ; $i<scalar @columns ; ++$i ){
				$row->{$columns[$i]} = $data[$i];
			}
			push( @{$array}, $row );
		}
		# end of the current result set
		#if( $sepCount == 3 ){
		#}
	}
	# at the end, either push the current array, or set it
	if( $multiple ){
		push( @{$result}, $array );
	} else {
		$result = $array;
	}
	return $result;
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
	my $result = undef;
	my $dbms = Mods::Dbms::_buildDbms();
	Mods::Message::msgErr( "Dbms::restoreDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	Mods::Message::msgErr( "Dbms::restoreDatabase() database is mandatory, but is not specified" ) if !$parms->{database} && !$parms->{verifyonly};
	Mods::Message::msgErr( "Dbms::restoreDatabase() full backup is mandatory, but is not specified" ) if !$parms->{full};
	Mods::Message::msgErr( "Dbms::restoreDatabase() $parms->{diff}: file not found or not readable" ) if $parms->{diff} && ! -f $parms->{diff};
	if( !Mods::Toops::errs()){
		$result = Mods::Dbms::toPackage( 'apiRestoreDatabase', $dbms, $parms );
	}
	if( $result && $result->{ok} ){
		Mods::Message::msgVerbose( "Dbms::restoreDatabase() returning status='true'" );
	} else {
		Mods::Message::msgErr( "Dbms::restoreDatabase() $parms->{instance}\\$parms->{database} NOT OK" );
	}
	return $result && $result->{ok};
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
	Mods::Message::msgVerbose( "Dbms::setInstanceByName() entering with name='".( $name || '(undef)' )."'" );
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
		Mods::Message::msgErr( "no 'DBMSInstances' key, or name is undefined or is not defined in host configuration" );
	}
	Mods::Message::msgVerbose( "Dbms::setInstanceByName() returning with found='".( $instance || '(undef)' )."'" );
	return $instance;
}

# -------------------------------------------------------------------------------------------------
# address a function in the package which deserves the named instance
#  and returns the result which is expected to be a hash with (at least) a 'ok' key, or undef
sub toPackage {
	my ( $fname, $dbms, $parms ) = @_;
	my $result = undef;
	Mods::Message::msgErr( "Dbms::toPackage() function name must be specified" ) if !$fname;
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "Dbms::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
		$dbms = Mods::Dbms::_buildDbms() if !$dbms;
		my $package = $dbms->{config}{DBMSInstances}{$dbms->{instance}{name}}{package};
		Mods::Message::msgVerbose( "Dbms::toPackage() package='".( $package || '(undef)' )."'" );
		if( $package ){
			Module::Load::load( $package );
			#Module::Runtime::use_module( $package );
			if( $package->can( $fname )){
				$result = $package->$fname( $dbms, $parms );
			} else {
				Mods::Message::msgWarn( "Dbms::toPackage() package '$package' says it cannot '$fname'" );
			}
		} else {
			Mods::Message::msgErr( "unable to find a package to address '$dbms->{instance}{name}' instance" );
		}
	}
	Mods::Message::msgVerbose( "Dbms::toPackage() returning with result='".( defined $result ? ( $result->{ok} ? 'true':'false' ) : '(undef)' )."'" );
	return $result;
}

1;
