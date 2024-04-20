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
use Mods::Message qw( :all );
use Mods::Path;
use Mods::Toops;

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
	msgErr( "Dbms::backupDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	msgErr( "Dbms::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( "Dbms::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	if( !Mods::Toops::ttpErrs()){
		if( !$parms->{output} ){
			$parms->{output} = Mods::Dbms::computeDefaultBackupFilename( $dbms, $parms );
		}
		msgOut( "backuping to '$parms->{output}'" );
		my $res = Mods::Dbms::toPackage( 'apiBackupDatabase', $dbms, $parms );
		$result->{status} = $res->{ok};
	}
	$result->{output} = $parms->{output};
	if( !$result->{status} ){
		msgErr( "Dbms::backupDatabase() $parms->{instance}\\$parms->{database} NOT OK" );
	} else {
		msgVerbose( "Dbms::backupDatabase() returning status='true' output='$result->{output}'" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the DBMS object passed to underlying packages
# <DBMS>
#  - instance: has been set at checkInstanceName() time
#    > name: instance name
#    > package: package name
#  - config
#    > <hostConfiguration>
#  - \exitCode
sub _buildDbms {
	my $TTPVars = Mods::Toops::TTPVars();
	# dbms is a special object created by TTP for the command
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
	msgVerbose( "Dbms::checkDatabaseExists() entering with instance='".( $instance || '(undef)' )."', database='".( $database || '(undef)' )."'" );
	msgErr( "Dbms::checkDatabaseExists() instance is mandatory, but is not specified" ) if !$instance;
	msgErr( "Dbms::checkDatabaseExists() database is mandatory, but is not specified" ) if !$database;
	if( !Mods::Toops::ttpErrs()){
		my $dbms = Mods::Dbms::_buildDbms();
		my $list = Mods::Dbms::getLiveDatabases( $dbms );
		$exists = true if grep( /$database/i, @{$list} );
	}
	msgVerbose( "checkDatabaseExists() returning ".( $exists ? 'true' : 'false' ));
	return $exists;
}

# -------------------------------------------------------------------------------------------------
# check that the provided instance name is valid on this machine
# - may be none if there is one and only one instance on the machine (though this emit a warning about future evolutions)
# - must be referenced in the json configuration file for the host
# (I):
# - the candidate instance name
# - an optional options hash with following keys:
#   > serviceConfig: a full service configuration (service definition, maybe overriden by the host configuration)
# (O):
# returns the validated instance name, or undef in case of an error
# this is not a garanty that this instance is rightly set and configured, and we cannot check that here, as we do not know what the caller is going to do
# if found, set up dbms -> instance -> { name, package } in TTPVars
#
# A default instance can be defined at site-level 'toops.json' configuration file. This default can be overriden for a particular service.
# At the host level, we only provide informations *about* instances, without defining their use. But we can suppose that this implies that instances are valid.
# The precedence order is site <overriden_by> service <overriden_by> host.
# But here, we do not manage service as we want check a '--instance' option by the fact
sub checkInstanceName {
	my ( $name, $opts ) = @_;
	$opts //= {};
	msgVerbose( "Dbms::checkInstanceName() entering with name='".( $name || '(undef)' )."'" );
	my $instance = undef;
	my $TTPVars = Mods::Toops::TTPVars();
	my $config = Mods::Toops::getHostConfig();
	if( $name ){
		# search for the name if host configuration
		if( exists( $config->{DBMS}{byInstance}{$name} )){
			msgVerbose( "found instance='$name' in host configuration" );
			$instance = $name;
		}
		# if not found, do we have a default instance in the site configuration file ?
		if( !defined( $instance )){
			if( exists( $TTPVars->{config}{toops}{DBMS}{instance} ) && $name eq $TTPVars->{config}{toops}{DBMS}{instance} ){
				msgVerbose( "found instance='$name' in site configuration" );
				$instance = $name;
			}
		}
		# if a name is specified, but not found, this is an error
		if( !defined( $instance )){
			msgErr( "instance='$name' is unknown by both host and site configurations" );
		}
	} else {
		$instance = _searchValue( $config, $opts->{serviceConfig}, [ 'DBMS', 'instance' ]);
		# if not found at all not found, this is an error
		if( !defined( $instance )){
			msgErr( "'--instance' option is not specified and no default can be found" );
		}
	}
	# if we have found a candidate instance, at least check that we can identify a package
	my $package = Mods::Toops::ttpVar([ 'DBMS', 'byInstance', $instance, 'package' ]);
	if( !$package ){
		msgErr( "unable to identify a package to address the '$instance' instance" );
		$instance = undef;
	}
	# if we have an instance and a package, then set the data
	if( $instance ){
		$TTPVars->{dbms}{instance} = {
			name => $instance,
			package => $package
		};
	}
	msgVerbose( "Dbms::checkInstanceName() returning with instance='".( $instance || '(undef)' )."'" );
	return $instance;
}

# ------------------------------------------------------------------------------------------------
# compute the default backup output filename for the current machine/intance/database
# making sure the output directory exists
# As of 2024 -1-31, default output filename is <host>-<instance>-<database>-<date>-<time>-<mode>.backup
# As of 2024 -2- 2, the backupDir is expected to be daily-ised, ie to contain a date part
# (I):
# - dbms, the DBMS object from _buildDbms()
# - parms is a hash ref with keys:
#   > instance name: mandatory
#   > database name: mandatory
#   > mode: defaulting to 'full'
sub computeDefaultBackupFilename {
	my ( $dbms, $parms ) = @_;
	msgVerbose( "Dbms::computeDefaultBackupFilename() entering" );
	my $output = undef;
	my $config = Mods::Toops::getHostConfig();
	msgErr( "Dbms::computeDefaultBackupFilename() instance is mandatory, but is not specified" ) if !$parms->{instance};
	msgErr( "Dbms::computeDefaultBackupFilename() database is mandatory, but is not specified" ) if !$parms->{database};
	my $mode = 'full';
	$mode = $parms->{mode} if exists $parms->{mode};
	msgErr( "Dbms::computeDefaultBackupFilename() mode must be 'full' or 'diff', found '$mode'" ) if $mode ne 'full' and $mode ne 'diff';
	# compute the dir and make sure it exists
	my $backupDir = Mods::Path::dbmsBackupsDir();
	if( !$backupDir ){
		msgWarn( "Dbms::computeDefaultBackupFilename() instance='$parms->{instance}' backupDir is not specified, set to default temp directory" );
		$backupDir = Mods::Toops::getDefaultTempDir();
	}
	# compute the filename
	my $fname = $dbms->{config}{name}.'-'.$parms->{instance}.'-'.$parms->{database}.'-'.localtime->strftime( '%y%m%d' ).'-'.localtime->strftime( '%H%M%S' ).'-'.$mode.'.backup';
	$output = File::Spec->catdir( $backupDir, $fname );
	msgVerbose( "Dbms::computeDefaultBackupFilename() computing output default as '$output'" );
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
		msgVerbose( "Dbms::displayTabularSql() expected an array, but found '$ref', so just give up" );
		return;
	}
	if( !scalar @{$result} ){
		msgVerbose( "Dbms::displayTabularSql() got an empty array, so just give up" );
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
		msgVerbose( "Dbms::displayTabularSql() expected an array of hashes, but found an array of '$ref', so just give up" );
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
			print pad( "| ".( defined $it->{$key} ? $it->{$key} : "" ), $lengths->{$key}+3, ' ' );
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
			msgVerbose( "do not display tabular result as opts->{tabular}='false'" );
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the list of tables in the databases
# the working-on instance has been set by checkInstanceName() function
sub getDatabaseTables {
	my ( $database ) = @_;
	my $result = Mods::Dbms::toPackage( 'apiGetDatabaseTables', undef, $database );
	return $result->{output} || [];
}

# -------------------------------------------------------------------------------------------------
# returns the list of instance live databases
# the working-on instance has been set by checkInstanceName() function
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
	msgErr( "Dbms::restoreDatabase() instance is mandatory, but is not specified" ) if !$parms->{instance};
	msgErr( "Dbms::restoreDatabase() database is mandatory, but is not specified" ) if !$parms->{database} && !$parms->{verifyonly};
	msgErr( "Dbms::restoreDatabase() full backup is mandatory, but is not specified" ) if !$parms->{full};
	msgErr( "Dbms::restoreDatabase() $parms->{diff}: file not found or not readable" ) if $parms->{diff} && ! -f $parms->{diff};
	if( !Mods::Toops::ttpErrs()){
		$result = Mods::Dbms::toPackage( 'apiRestoreDatabase', $dbms, $parms );
	}
	if( $result && $result->{ok} ){
		msgVerbose( "Dbms::restoreDatabase() returning status='true'" );
	} else {
		msgErr( "Dbms::restoreDatabase() $parms->{instance}\\$parms->{database} NOT OK" );
	}
	return $result && $result->{ok};
}

# ------------------------------------------------------------------------------------------------
# Search for a value according to the rules of precedence:
# - the host configuration through a 'Service.<service>.DBMS.instance' key in the service section
# - the host configuration through a 'DBMS.instance' key (acts as a default for all services in this host)
# - the service configuration as a 'DBMS.instance' key (acts as a default for all hosts which define this service)
# - the site configuration as a 'DBMS.instance' key (acts as a default for all services and hosts)
# First (non empty) found wins, which doesn't imply that the found instance exists and is valid.
# (I):
# - the host configuration
# - the service configuration
# - the search value as a ref to an array of successive keys, e.g. [ 'DBMS', 'instance' ] for the rules example
# (O):
# - the searched value or undef if none has been found
sub _searchValue {
	my ( $hostConfig, $serviceConfig, $keys ) = @_;
	my $result = undef;
	# search in the service section of the host configuration
	if( !defined( $result )){
		my @serviceKeys = @{$keys};
		unshift( @serviceKeys, "Services", $serviceConfig->{name} );
		$result = Mods::Toops::varSearch( \@serviceKeys, $hostConfig );
		msgVerbose( "'$result' found with (".join( ',', @serviceKeys ).") in service section of host configuration" ) if defined $result;
	}
	# search at the host level
	if( !defined( $result )){
		$result = Mods::Toops::varSearch( $keys, $hostConfig );
		msgVerbose( "'$result' found with (".join( ',', @{$keys} ).") in global section of host configuration" ) if defined $result;
	}
	# search in the service configuration
	if( !defined( $result )){
		$result = Mods::Toops::varSearch( $keys, $serviceConfig );
		msgVerbose( "'$result' found with (".join( ',', @{$keys} ).") in service configuration" ) if defined $result;
	}
	# search in the site configuration
	if( !defined( $result )){
		my $TTPVars = Mods::Toops::TTPVars();
		$result = Mods::Toops::varSearch( $keys, $TTPVars->{config}{toops} );
		msgVerbose( "'$result' found with (".join( ',', @{$keys} ).") in site configuration" ) if defined $result;
	}
	msgVerbose( "(".join( ',', @{$keys} ).") not found" ) if !defined $result;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# address a function in the package which deserves the named instance
#  and returns the result which is expected to be a hash with (at least) a 'ok' key, or undef
sub toPackage {
	my ( $fname, $dbms, $parms ) = @_;
	my $result = undef;
	msgErr( "Dbms::toPackage() function name must be specified" ) if !$fname;
	if( !Mods::Toops::ttpErrs()){
		msgVerbose( "Dbms::toPackage() entering with fname='".( $fname || '(undef)' )."'" );
		$dbms = Mods::Dbms::_buildDbms() if !$dbms;
		my $package = $dbms->{instance}{package};
		msgVerbose( "Dbms::toPackage() package='".( $package || '(undef)' )."'" );
		if( $package ){
			Module::Load::load( $package );
			#Module::Runtime::use_module( $package );
			if( $package->can( $fname )){
				$result = $package->$fname( $dbms, $parms );
			} else {
				msgWarn( "Dbms::toPackage() package '$package' says it cannot '$fname'" );
			}
		} else {
			msgErr( "unable to find a package to address '$dbms->{instance}{name}' instance" );
		}
	}
	msgVerbose( "Dbms::toPackage() returning with result='".( defined $result ? ( $result->{ok} ? 'true':'false' ) : '(undef)' )."'" );
	return $result;
}

1;
