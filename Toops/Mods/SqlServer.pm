# Copyright (@) 2023-2024 PWI Consulting

package Mods::SqlServer;

use strict;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use Time::Piece;
use Win32::SqlServer qw( :DEFAULT :consts );

use Mods::Constants qw( :all );
use Mods::Toops;

# the list of system databases to be excluded
my $systemDatabases = [
	'master',
	'tempdb',
	'model',
	'msdb'
];

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - output: mandatory
# - mode: mandatory, full|diff
# - dummy: true|false, defaulting to false
# return true|false
sub apiBackupDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = false;
	Mods::Toops::msgErr( "SqlServer::backupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Toops::msgErr( "SqlServer::backupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	Mods::Toops::msgErr( "SqlServer::backupDatabase() output is mandatory, but is not specified" ) if !$parms->{output};
	if( !Mods::Toops::errs()){
		my $tstring = localtime->strftime( '%Y-%m-%d %H:%M:%S' );
		# if full
		my $options = "NOFORMAT, NOINIT, MEDIANAME='SQLServerBackups'";
		my $label = "Full";
		# if diff
		if( $parms->{mode} eq 'diff' ){
			$options .= ", DIFFERENTIAL";
			$label = "Differential";
		}
		$parms->{sql} = "USE master;
BACKUP DATABASE $parms->{database} TO DISK='$parms->{output}' WITH $options, NAME='$parms->{database} $label Backup $tstring';";
		Mods::Toops::msgVerbose( "SqlServer::backupDatabase() sql='$parms->{sql}'" );
		$result = Mods::SqlServer::sqlNoResult( $dbms, $parms );
	}
	Mods::Toops::msgVerbose( "SqlServer::backupDatabase() returns '".( $result ? 'true':'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the first account defined for the named instance
sub apiExecSqlCommand {
	my ( $me, $dbms, $sql ) = @_;
	my $result = undef;
	my $sqlsrv = undef;
	Mods::Toops::msgErr( "SqlServer::execSqlCommand() instance is mandaotry, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	if( !Mods::Toops::errs()){
		Mods::Toops::msgVerbose( "SqlServer::execSqlCommand() entering with instance='$dbms->{instance}{name}'" );
		$sqlsrv = Mods::SqlServer::_connect( $dbms );
	}
	if( !Mods::Toops::errs() && $sqlsrv ){
		$result = $sqlsrv->sql( $sql );
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
sub apiGetDatabaseTables {
	my ( $me, $dbms, $database ) = @_;
	my $result = undef;
	my $instance = $dbms->{instance}{name};
	Mods::Toops::msgVerbose( "SqlServer::getDatabaseTables() entering with instance='".( $instance || '(undef)' )."', database='".( $database || '(undef)' )."'" );
	if( $instance && $database ){
		my $sqlsrv = Mods::SqlServer::_connect( $dbms );
		if( !Mods::Toops::errs() && $sqlsrv ){
			$result = [];
			# get an array of { TABLE_SCHEMA,TABLE_NAME } hashes
			my $res = $sqlsrv->sql( "SELECT TABLE_SCHEMA,TABLE_NAME FROM $database.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
			foreach my $it ( @{$res} ){
				push( @{$result}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
			}
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# get and returns the list of live databases
# the passed-in object is a hash with following keys:
# - config: a reference to the host config
# - instance: a hash with:
#   > name: the name of the addressed instance
#   > data: the host configuration for this instance
# - exitCode: a reference to the global exit code
sub apiGetInstanceDatabases {
	my ( $me, $dbms ) = @_;
	my $result = undef;
	my $instance = $dbms->{instance}{name};
	Mods::Toops::msgVerbose( "SqlServer::getLiveDatabases() entering with instance='".$instance || '(undef)'."'" );
	if( $instance ){
		my $sqlsrv = Mods::SqlServer::_connect( $dbms );
		if( !Mods::Toops::errs() && $sqlsrv ){
			$result = [];
			my $res = $sqlsrv->sql( "select name from master.sys.databases order by name" );
			foreach( @{$res} ){
				my $dbname = $_->{'name'};
				if( !grep( /^$dbname$/, @{$systemDatabases} )){
					push( @{$result}, $dbname );
				}
			}
			Mods::Toops::msgVerbose( "SqlServer::getLiveDatabases() found ".scalar @{$result}." databases: ".join( ', ', @{$result} ));
		}
	} else {
		Mods::Toops::msgErr( "SqlServer::getLiveDatabases() instance is mandatory, not specified" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - full: mandatory
# - diff: defaults to '' (full restore only)
# - verifyonly, defaulting to false
# returns true|false
sub apiRestoreDatabase {
	my ( $me, $dbms, $parms ) = @_;
	Mods::Toops::msgVerbose( "SqlServer::restoreDatabase() entering..." );
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $full = $parms->{full};
	my $diff = $parms->{diff} || '';
	my $res = false;
	my $sqlsrv = undef;
	my $verifyonly = false;
	$verifyonly = $parms->{verifyonly} if exists $parms->{verifyonly};
	msgErr( "SqlServer::restoreDatabase() instance is mandatory, not specified" ) if !$instance;
	msgErr( "SqlServer::restoreDatabase() database is mandatory, not specified" ) if !$database && !$verifyonly;
	msgErr( "SqlServer::restoreDatabase() full is mandatory, not specified" ) if !$full;
	if( !Mods::Toops::errs()){
		if( $verifyonly || _restoreDatabaseSetOffline( $dbms, $parms )){
			$parms->{'file'} = $full;
			$parms->{'last'} = length $diff == 0 ? true : false;
			if( $verifyonly ){
				$res = _restoreDatabaseVerify( $dbms, $parms );
			} else {
				$res = _restoreDatabaseFile( $dbms, $parms );
			}
			if( $res && length $diff ){
				$parms->{'file'} = $diff;
				$parms->{'last'} = true;
				if( $verifyonly ){
					$res &= _restoreDatabaseVerify( $dbms, $parms );
				} else {
					$res &= _restoreDatabaseFile( $dbms, $parms );
				}
			}
		}
	}
	return $res;
}

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
sub _connect {
	my ( $dbms ) = @_;
	my $sqlsrv = $dbms->{instance}{sqlsrv};
	if( $sqlsrv ){
		Mods::Toops::msgVerbose( "SqlServer::connect() instance already connected" );
	} else {
		my $instance = $dbms->{instance}{name};
		if( $instance ){
			Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
			my( $account, $passwd ) = Mods::SqlServer::_getCredentials( $dbms );
			if( length $account && length $passwd ){
				my $server = $dbms->{config}{name}."\\".$instance;
				Mods::Toops::msgVerbose( "SqlServer::connect() calling sql_init with server='$server', account='$account'..." );
				$sqlsrv = Win32::SqlServer::sql_init( $server, $account, $passwd );
				Mods::Toops::msgVerbose( "SqlServer::connect() sqlsrv->isconnected()=".$sqlsrv->isconnected());
				#print Dumper( $sqlsrv );
				if( $sqlsrv && $sqlsrv->isconnected()){
					$sqlsrv->{ErrInfo}{MaxSeverity} = 17;
					$sqlsrv->{ErrInfo}{SaveMessages} = 1;
					Mods::Toops::msgVerbose( "SqlServer::connect() successfully connected" );
					$dbms->{instance}{sqlsrv} = $sqlsrv;
				} else {
					Mods::Toops::msgErr( "SqlServer::connect() unable to connect to '$instance' instance" );
					$sqlsrv = undef;
				}
			} else {
				Mods::Toops::msgErr( "SqlServer::connect() unable to get account/password couple" );
			}
		} else {
			Mods::Toops::msgErr( "SqlServer::connect() instance is mandatory, not specified" );
		}
	}
	return $sqlsrv;
}

# ------------------------------------------------------------------------------------------------
# whether the named database exists ?
# return true|false
sub _databaseExists {
	my ( $dbms, $database ) = @_;
	my $result = false;
	my $sql = "select name from sys.databases where name = '$database';";
	my $sqlsrv = Mods::SqlServer::_connect( $dbms );
	my $res = $sqlsrv->sql( $sql );
	$result = scalar @{$res} == 1;
	Mods::Toops::msgVerbose( "SqlServer::_databaseExists() database='$database' exists='".( $result ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the first account defined for the named instance
sub _getCredentials {
	my ( $dbms ) = @_;
	my $account = undef;
	my $passwd = undef;
	my $instance = $dbms->{instance}{name};
	if( $instance ){
		$account = ( keys %{$dbms->{instance}{data}{accounts}} )[0];
		$passwd = $dbms->{instance}{data}{accounts}{$account};
		Mods::Toops::msgVerbose( "SqlServer::getCredentials() got account='".( $account || '(undef)' )."'" );
	} else {
		Mods::Toops::msgErr( "SqlServer::getCredentials() instance is mandatory, not specified" );
	}
	return ( $account, $passwd );
}

# -------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# in this first phase, set it first offline (if it exists)
# return true|false
sub _restoreDatabaseSetOffline {
	my ( $dbms, $parms ) = @_;
	my $database = $parms->{database};
	my $result = true;
	if( _databaseExists( $dbms, $database )){
		$parms->{sql} = "ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE;";
		$result = Mods::SqlServer::sqlNoResult( $dbms, $parms );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# return true|false
sub _restoreDatabaseFile {
	my ( $dbms, $parms ) = @_;
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $fname = $parms->{file};
	my $last = $parms->{last};
	#
	Mods::Toops::msgVerbose( "SqlServer::restoreDatabaseFile() restoring $fname" );
	my $sqlsrv = _connect( $dbms );
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = _restoreDatabaseMove( $dbms, $parms );
	$parms->{'sql'} = "RESTORE DATABASE $database FROM DISK='$fname' WITH $recovery, $move;";
	return Mods::SqlServer::sqlNoResult( $dbms, $parms );
}

# -------------------------------------------------------------------------------------------------
# returns the move option in case of the datapath is different from the source or the target database has changed
sub _restoreDatabaseMove {
	my ( $dbms, $parms ) = @_;
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $fname = $parms->{file};
	my $sqlsrv = _connect( $dbms );
	my $content = $sqlsrv->sql( "RESTORE FILELISTONLY FROM DISK='$fname'" );
	my $move = '';
	my $sqlDataPath = Mods::Toops::pathWithTrailingSeparator( $dbms->{config}{DBMSInstances}{$parms->{instance}}{dataPath} );
	foreach( @{$content} ){
		my $row = $_;
		$move .= ', ' if length $move;
		my ( $vol, $dirs, $fname ) = File::Spec->splitpath( $sqlDataPath );
		my $target_file = File::Spec->catpath( $vol, $dirs, $database.( $row->{Type} eq 'D' ? '.mdf' : '.ldf' ));
		$move .= "MOVE '".$row->{'LogicalName'}."' TO '$target_file'";
	}
	return $move;
}

# -------------------------------------------------------------------------------------------------
# verify the restorability of the file
# return true|false
sub _restoreDatabaseVerify {
	my ( $dbms, $parms ) = @_;
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $fname = $parms->{file};
	Mods::Toops::msgVerbose( "SqlServer::restoreDatabaseVerify() verifying $fname" );
	my $move = _restoreDatabaseMove( $dbms, $parms );
	$parms->{'sql'} = "RESTORE VERIFYONLY FROM DISK='$fname' WITH $move;";
	return Mods::SqlServer::sqlNoResult( $dbms, $parms );
}

# -------------------------------------------------------------------------------------------------
# execute a SQL request with no output
# parms is a hash ref with keys:
# - instance|sqlsrv: mandatory
# - sql: mandatory
# - dummy: true|false, defaulting to false
# return true|false
sub sqlNoResult {
	my ( $dbms, $parms ) = @_;
	Mods::Toops::msgErr( "SqlServer::sqlNoResult() sql is mandatory, but is not specified" ) if !$parms->{sql};
	my $result = false;
	my $sqlsrv = undef;
	if( !Mods::Toops::errs()){
		$sqlsrv = Mods::SqlServer::_connect( $dbms );
	}
	if( !Mods::Toops::errs()){
		Mods::Toops::msgVerbose( "SqlServer::sqlNoResult() executing '$parms->{sql}'" );
		if( exists( $parms->{dummy} ) && $parms->{dummy} ){
			Mods::Toops::msgDummy( "executing '$parms->{sql}'" );
			$result = true;
		} else {
			my $merged = capture_merged {
				$sqlsrv->sql( $parms->{sql}, Win32::SqlServer::NORESULT );
			};
			$result = $sqlsrv->sql_has_errors() ? false : true;
			my @merged = split( /[\r\n]/, $merged );
			foreach my $line ( @merged ){
				chomp( $line );
				$line =~ s/^\s*//;
				$line =~ s/\s*$//;
				print " $line".EOL if length $line;
			}
			delete $sqlsrv->{ErrInfo}{Messages};
		}
	}
	Mods::Toops::msgVerbose( "SqlServer::sqlNoResult() returns '".( $result ? 'true':'false' )."'" );
	return $result;
}

=pod

# ------------------------------------------------------------------------------------------------
# update database statistics
# parms is a hash ref with keys:
# - instance: mandatory
# - db: mandatory
# - verbose: default to false
# return true|false
sub updateStatistics( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $db = $parms->{'db'};
	my $verbose = $parms->{'verbose'} || false;
	msgErr( "instance is mandatory, not specified" ) if !$instance;
	msgErr( "db is mandatory, not specified" ) if !$db;
	my $res = false;
	if( !errs()){
		$parms->{'sql'} = "USE $db; EXEC sp_updatestats;";
		$res = Mods::SqlServer::sqlNoResult( $parms );
	}
	return $res;
}

=cut

1;
