# Copyright (@) 2023-2024 PWI Consulting

package Mods::SqlServer;

use strict;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use Path::Tiny;
use Time::Piece;
use Win32::SqlServer qw( :DEFAULT :consts );

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;
use Mods::Toops;

# the list of system databases to be excluded
my $systemDatabases = [
	'master',
	'tempdb',
	'model',
	'msdb'
];

# the list of system tables to be excluded
my $systemTables = [
	'dtproperties',
	'sysdiagrams'
];

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - output: mandatory
# - mode: mandatory, full|diff
# - compress: true|false
# (O):
# returns a hash with following keys:
# - ok: true|false
# - stdout: a copy of lines outputed on stdout as an array ref
sub apiBackupDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	Mods::Message::msgErr( "SqlServer::apiBackupDatabase() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	Mods::Message::msgErr( "SqlServer::apiBackupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Message::msgErr( "SqlServer::apiBackupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	Mods::Message::msgErr( "SqlServer::apiBackupDatabase() output is mandatory, but is not specified" ) if !$parms->{output};
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::apiBackupDatabase() entering with instance='$dbms->{instance}{name}' database='$parms->{database}' mode='$parms->{mode}'..." );
		my $tstring = localtime->strftime( '%Y-%m-%d %H:%M:%S' );
		# if full
		my $options = "NOFORMAT, NOINIT, MEDIANAME='SQLServerBackups'";
		my $label = "Full";
		# if diff
		if( $parms->{mode} eq 'diff' ){
			$options .= ", DIFFERENTIAL";
			$label = "Differential";
		}
		$options .= ", COMPRESSION" if exists $parms->{compress} && $parms->{compress};
		$parms->{sql} = "USE master; BACKUP DATABASE $parms->{database} TO DISK='$parms->{output}' WITH $options, NAME='$parms->{database} $label Backup $tstring';";
		Mods::Message::msgVerbose( "SqlServer::apiBackupDatabase() sql='$parms->{sql}'" );
		$result = _sqlExec( $dbms, $parms->{sql} );
	}
	Mods::Message::msgVerbose( "SqlServer::apiBackupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# execute a SQL command and returns its result
# (I):
# - the name of this dynamically addressed module as a string 'Mods::SqlServer'
# - the connection object as provided by Dbms.pm
# - an object with following keys:
#   > command: the sql command
#   > opts: an optional options hash which following keys:
#     - multiple: whether several result sets are expected, defaulting to false
# (O):
# returns a hash with following keys:
# - ok: true|false
# - result: the result set as an array ref
# - stdout: a copy of lines outputed on stdout as an array ref
sub apiExecSqlCommand {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	Mods::Message::msgErr( "SqlServer::apiExecSqlCommand() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	Mods::Message::msgErr( "SqlServer::apiExecSqlCommand() command is mandatory, but not specified" ) if !$parms || !$parms->{command};
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::apiExecSqlCommand() entering with instance='$dbms->{instance}{name}' sql='$parms->{command}'" );
		my $resultStyle = Win32::SqlServer::SINGLESET;
		$resultStyle = Win32::SqlServer::MULTISET if $parms->{opts} && $parms->{opts}{multiple};
		my $opts = {
			resultStyle => $resultStyle
		};
		$result = _sqlExec( $dbms, $parms->{command}, $opts );
	}
	Mods::Message::msgVerbose( "SqlServer::apiExecSqlCommand() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines
sub apiGetDatabaseTables {
	my ( $me, $dbms, $database ) = @_;
	my $result = { ok => false, output => [] };
	Mods::Message::msgErr( "SqlServer::apiGetDatabaseTables() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	Mods::Message::msgErr( "SqlServer::apiGetDatabaseTables() database is mandatory, but not specified" ) if !$database;
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::apiGetDatabaseTables() entering with instance='$dbms->{instance}{name}', database='$database'" );
		$result = _sqlExec( $dbms,  "SELECT TABLE_SCHEMA,TABLE_NAME FROM $database.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
		if( $result->{ok} ){
			foreach my $it ( @{$result->{result}} ){
				if( !grep( /^$it->{TABLE_NAME}$/, @{$systemTables} )){
					push( @{$result->{output}}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
				}
			}
			Mods::Message::msgVerbose( "SqlServer::apiGetDatabaseTables() found ".scalar @{$result->{output}}." tables" );
		}
	}
	Mods::Message::msgVerbose( "SqlServer::apiGetDatabaseTables() result='".( $result->{ok} ? 'true' : 'false' )."'" );
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
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines
sub apiGetInstanceDatabases {
	my ( $me, $dbms ) = @_;
	my $result = { ok => false, output => [] };
	Mods::Message::msgErr( "SqlServer::apiGetInstanceDatabases() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::apiGetInstanceDatabases() entering with instance='$dbms->{instance}{name}'" );
		$result = _sqlExec( $dbms, "select name from master.sys.databases order by name" );
		if( $result->{ok} ){
			foreach( @{$result->{result}} ){
				my $dbname = $_->{'name'};
				if( !grep( /^$dbname$/, @{$systemDatabases} )){
					push( @{$result->{output}}, $dbname );
				}
			}
			Mods::Message::msgVerbose( "SqlServer::apiGetInstanceDatabases() found ".scalar @{$result->{output}}." databases" );
		}
	}
	Mods::Message::msgVerbose( "SqlServer::apiGetInstanceDatabases() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - database: mandatory
# - full: mandatory
# - diff: defaults to '' (full restore only)
# - verifyonly, defaulting to false
# (O):
# returns a hash with following keys:
# - ok: true|false
sub apiRestoreDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	my $verifyonly = false;
	$verifyonly = $parms->{verifyonly} if exists $parms->{verifyonly};
	Mods::Message::msgErr( "SqlServer::apiRestoreDatabase() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	Mods::Message::msgErr( "SqlServer::apiRestoreDatabase() database is mandatory, not specified" ) if !$parms->{database} && !$verifyonly;
	Mods::Message::msgErr( "SqlServer::apiRestoreDatabase() full is mandatory, not specified" ) if !$parms->{full};
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::apiRestoreDatabase() entering with instance='$dbms->{instance}{name}' verifyonly='$verifyonly'..." );
		my $diff = $parms->{diff} || '';
		if( $verifyonly || _restoreDatabaseSetOffline( $dbms, $parms )){
			$parms->{'file'} = $parms->{full};
			$parms->{'last'} = length $diff == 0 ? true : false;
			if( $verifyonly ){
				$result->{ok} = _restoreDatabaseVerify( $dbms, $parms );
			} else {
				$result->{ok} = _restoreDatabaseFile( $dbms, $parms );
			}
			if( $result->{ok} && length $diff ){
				$parms->{'file'} = $diff;
				$parms->{'last'} = true;
				if( $verifyonly ){
					$result->{ok} &= _restoreDatabaseVerify( $dbms, $parms );
				} else {
					$result->{ok} &= _restoreDatabaseFile( $dbms, $parms );
				}
			}
		}
	}
	Mods::Message::msgVerbose( "SqlServer::apiRestoreDatabase() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
sub _connect {
	my ( $dbms ) = @_;
	my $sqlsrv = $dbms->{instance}{sqlsrv};
	if( $sqlsrv ){
		Mods::Message::msgVerbose( "SqlServer::_connect() instance already connected" );
	} else {
		my $instance = $dbms->{instance}{name};
		if( $instance ){
			Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
			my( $account, $passwd ) = Mods::SqlServer::_getCredentials( $dbms );
			if( length $account && length $passwd ){
				my $server = $dbms->{config}{name}."\\".$instance;
				# SQLServer 2008R2 doesn't like have a server connection string with MSSQLSERVER default instance
				$server = undef if $instance eq "MSSQLSERVER";
				Mods::Message::msgVerbose( "SqlServer::_connect() calling sql_init with server='".( $server || '(undef)' )."', account='$account'..." );
				$sqlsrv = Win32::SqlServer::sql_init( $server, $account, $passwd );
				Mods::Message::msgVerbose( "SqlServer::_connect() sqlsrv->isconnected()=".$sqlsrv->isconnected());
				#print Dumper( $sqlsrv );
				if( $sqlsrv && $sqlsrv->isconnected()){
					$sqlsrv->{ErrInfo}{MaxSeverity} = 17;
					$sqlsrv->{ErrInfo}{SaveMessages} = 1;
					Mods::Message::msgVerbose( "SqlServer::_connect() successfully connected" );
					$dbms->{instance}{sqlsrv} = $sqlsrv;
				} else {
					Mods::Message::msgErr( "SqlServer::_connect() unable to connect to '$instance' instance" );
					$sqlsrv = undef;
				}
			} else {
				Mods::Message::msgErr( "SqlServer::_connect() unable to get account/password couple" );
			}
		} else {
			Mods::Message::msgErr( "SqlServer::_connect() instance is mandatory, not specified" );
		}
	}
	return $sqlsrv;
}

# ------------------------------------------------------------------------------------------------
# whether the named database exists ?
# return true|false
sub _databaseExists {
	my ( $dbms, $database ) = @_;
	my $result = _sqlExec( $dbms, "select name from sys.databases where name = '$database';" );
	my $exists = $result->{ok} && scalar @{$result->{result}} == 1;
	Mods::Message::msgVerbose( "SqlServer::_databaseExists() database='$database' exists='".( $exists ? 'true' : 'false' )."'" );
	return $exists;
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
		Mods::Message::msgVerbose( "SqlServer::_getCredentials() got account='".( $account || '(undef)' )."'" );
	} else {
		Mods::Message::msgErr( "SqlServer::_getCredentials() instance is mandatory, not specified" );
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
		my $res = _sqlExec( $dbms, "ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE;" );
		$result = $res->{ok};
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
	Mods::Message::msgVerbose( "SqlServer::_restoreDatabaseFile() restoring $fname" );
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = _restoreDatabaseMove( $dbms, $parms );
	my $result = true;
	if( $move ){
		my $res = _sqlExec( $dbms, "RESTORE DATABASE $database FROM DISK='$fname' WITH $recovery, $move;" );
		$result = $res->{ok};
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the move option in case of the datapath is different from the source or the target database has changed
sub _restoreDatabaseMove {
	my ( $dbms, $parms ) = @_;
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $fname = $parms->{file};
	my $result = _sqlExec( $dbms, "RESTORE FILELISTONLY FROM DISK='$fname'" );
	my $move = undef;
	if( !scalar @{$result->{result}} ){
		Mods::Message::msgErr( "SqlServer::_restoreDatabaseMove() unable to get the files list of the backup set" );
	} else {
		my $sqlDataPath = Mods::Path::withTrailingSeparator( $dbms->{config}{DBMSInstances}{$parms->{instance}}{dataPath} );
		foreach( @{$result->{result}} ){
			my $row = $_;
			$move .= ', ' if length $move;
			my ( $vol, $dirs, $fname ) = File::Spec->splitpath( $sqlDataPath );
			my $target_file = File::Spec->catpath( $vol, $dirs, $database.( $row->{Type} eq 'D' ? '.mdf' : '.ldf' ));
			$move .= "MOVE '".$row->{'LogicalName'}."' TO '$target_file'";
		}
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
	Mods::Message::msgVerbose( "SqlServer::_restoreDatabaseVerify() verifying $fname" );
	my $move = _restoreDatabaseMove( $dbms, $parms );
	my $res = _sqlExec( $dbms, "RESTORE VERIFYONLY FROM DISK='$fname' WITH $move;" );
	return $res->{ok};
}

# -------------------------------------------------------------------------------------------------
# execute a SQL request
# (I):
# - dbms: the connection object as provided by Dbms.pm
# - sql: the command
# - opts: an optional options hash with following keys:
#   > printStdout, defaulting to true
#   > resultStyle, defaulting to SINGLESET
# (O):
# returns hash with following keys:
# - ok: true|false
# - result: as an array ref
# - stdout: as an array ref
sub _sqlExec {
	my ( $dbms, $sql, $opts ) = @_;
	$opts //= {};
	Mods::Message::msgErr( "SqlServer::_sqlExec() sql is mandatory, but is not specified" ) if !$sql;
	my $result = { ok => false, stdout => [] };
	my $sqlsrv = undef;
	if( !Mods::Toops::errs()){
		$sqlsrv = Mods::SqlServer::_connect( $dbms );
	}
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "SqlServer::_sqlExec() executing '$sql'" );
		$result->{ok} = Mods::Message::msgDummy( $sql );
		if( !Mods::Toops::wantsDummy()){
			my $printStdout = true;
			$printStdout = $opts->{printStdout} if exists $opts->{printStdout};
			my $resultStyle = Win32::SqlServer::SINGLESET;
			$resultStyle = $opts->{resultStyle} if exists $opts->{resultStyle};
			my $merged = capture_merged { $result->{result} = $sqlsrv->sql( $sql, $resultStyle )};
			my @merged = split( /[\r\n]/, $merged );
			foreach my $line ( @merged ){
				chomp( $line );
				$line =~ s/^\s*//;
				$line =~ s/\s*$//;
				if( length $line ){
					print " $line".EOL if $printStdout;
					push( @{$result->{stdout}}, $line );
				}
			}
			$result->{ok} = $sqlsrv->sql_has_errors() ? false : true;
			delete $sqlsrv->{ErrInfo}{Messages};
		}
	}
	Mods::Message::msgVerbose( "SqlServer::_sqlExec() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

1;
