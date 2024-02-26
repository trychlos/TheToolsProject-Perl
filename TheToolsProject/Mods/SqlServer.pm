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
# - compress: true|false
# (O):
# returns a hash with following keys:
# - ok: true|false
sub apiBackupDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	Mods::Toops::msgErr( "SqlServer::apiBackupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	Mods::Toops::msgErr( "SqlServer::apiBackupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	Mods::Toops::msgErr( "SqlServer::apiBackupDatabase() output is mandatory, but is not specified" ) if !$parms->{output};
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
		$options .= ", COMPRESSION" if exists $parms->{compress} && $parms->{compress};
		$parms->{sql} = "USE master;
BACKUP DATABASE $parms->{database} TO DISK='$parms->{output}' WITH $options, NAME='$parms->{database} $label Backup $tstring';";
		Mods::Toops::msgVerbose( "SqlServer::apiBackupDatabase() sql='$parms->{sql}'" );
		$result->{ok} = _sqlNoResult( $dbms, $parms );
	}
	Mods::Toops::msgVerbose( "SqlServer::apiBackupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# execute a SQL command and returns its result
# doesn't try to capture the output at the moment
# doesn't honor '--dummy' option when the command is a SELECT sentence
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines (which may be errors or normal command output)
sub apiExecSqlCommand {
	my ( $me, $dbms, $sql ) = @_;
	my $result = { ok => false };
	Mods::Toops::msgErr( "SqlServer::apiExecSqlCommand() instance is mandatory, but not specified" ) if !$dbms || !$dbms->{instance} || !$dbms->{instance}{name};
	if( !Mods::Toops::errs()){
		Mods::Toops::msgVerbose( "SqlServer::apiExecSqlCommand() entering with instance='$dbms->{instance}{name}' sql='$sql'" );
		if( $sql =~ /^SELECT /i ){
			my $sqlsrv = Mods::SqlServer::_connect( $dbms );
			$result->{output} = $sqlsrv->sql( $sql );
			$result->{ok} = $sqlsrv->sql_has_errors() ? false : true;
		} else {
			my( $account, $passwd ) = Mods::SqlServer::_getCredentials( $dbms );
			if( length $account && length $passwd ){
				my $server = $dbms->{config}{name}."\\".$dbms->{instance}{name};
				my $tempfname = Mods::Toops::getTempFileName();
				Mods::Toops::msgVerbose( "tempFileName='$tempfname'" );
				my $command = "sqlcmd -Q \"$sql\" -S $server -U $account -V16 -P";
				Mods::Toops::msgVerbose( "executing '$command xxxxxx'" );
				my $stdout = `$command $passwd -o $tempfname`;
				$result->{ok} = ( $? == 0 ) ? true : false;
				if( $stdout ){
					print $stdout;
					Mods::Toops::msgLog( $stdout );
				}
				my $temp = path( $tempfname );
				my @lines = $temp->lines_utf8;
				$result->{output} = \@lines;
			}
		}
	}
	Mods::Toops::msgVerbose( "SqlServer::apiExecSqlCommand() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines (which may be errors or normal command output)
sub apiGetDatabaseTables {
	my ( $me, $dbms, $database ) = @_;
	my $result = { ok => false };
	my $instance = $dbms->{instance}{name};
	Mods::Toops::msgVerbose( "SqlServer::apiGetDatabaseTables() entering with instance='".( $instance || '(undef)' )."', database='".( $database || '(undef)' )."'" );
	if( $instance && $database ){
		my $sqlsrv = Mods::SqlServer::_connect( $dbms );
		if( !Mods::Toops::errs() && $sqlsrv ){
			$result->{output} = [];
			# get an array of { TABLE_SCHEMA,TABLE_NAME } hashes
			my $res = $sqlsrv->sql( "SELECT TABLE_SCHEMA,TABLE_NAME FROM $database.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
			foreach my $it ( @{$res} ){
				push( @{$result->{output}}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
			}
			Mods::Toops::msgVerbose( "SqlServer::apiGetDatabaseTables() found ".scalar @{$result->{output}}." tables" );
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
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines (which may be errors or normal command output)
sub apiGetInstanceDatabases {
	my ( $me, $dbms ) = @_;
	my $result = { ok => false };
	my $instance = $dbms->{instance}{name};
	Mods::Toops::msgVerbose( "SqlServer::apiGetInstanceDatabases() entering with instance='".$instance || '(undef)'."'" );
	if( $instance ){
		my $sqlsrv = Mods::SqlServer::_connect( $dbms );
		if( !Mods::Toops::errs() && $sqlsrv ){
			$result->{output} = [];
			my $res = $sqlsrv->sql( "select name from master.sys.databases order by name" );
			foreach( @{$res} ){
				my $dbname = $_->{'name'};
				if( !grep( /^$dbname$/, @{$systemDatabases} )){
					push( @{$result->{output}}, $dbname );
				}
			}
			Mods::Toops::msgVerbose( "SqlServer::apiGetInstanceDatabases() found ".scalar @{$result->{output}}." databases" );
		}
	} else {
		Mods::Toops::msgErr( "SqlServer::apiGetInstanceDatabases() instance is mandatory, not specified" );
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
# (O):
# returns a hash with following keys:
# - ok: true|false
sub apiRestoreDatabase {
	my ( $me, $dbms, $parms ) = @_;
	Mods::Toops::msgVerbose( "SqlServer::apiRestoreDatabase() entering..." );
	my $instance = $parms->{instance};
	my $database = $parms->{database};
	my $full = $parms->{full};
	my $diff = $parms->{diff} || '';
	my $result = { ok => false };
	my $sqlsrv = undef;
	my $verifyonly = false;
	$verifyonly = $parms->{verifyonly} if exists $parms->{verifyonly};
	msgErr( "SqlServer::apiRestoreDatabase() instance is mandatory, not specified" ) if !$instance;
	msgErr( "SqlServer::apiRestoreDatabase() database is mandatory, not specified" ) if !$database && !$verifyonly;
	msgErr( "SqlServer::apiRestoreDatabase() full is mandatory, not specified" ) if !$full;
	if( !Mods::Toops::errs()){
		if( $verifyonly || _restoreDatabaseSetOffline( $dbms, $parms )){
			$parms->{'file'} = $full;
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
	return $result;
}

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
sub _connect {
	my ( $dbms ) = @_;
	my $sqlsrv = $dbms->{instance}{sqlsrv};
	if( $sqlsrv ){
		Mods::Toops::msgVerbose( "SqlServer::_connect() instance already connected" );
	} else {
		my $instance = $dbms->{instance}{name};
		if( $instance ){
			Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
			my( $account, $passwd ) = Mods::SqlServer::_getCredentials( $dbms );
			if( length $account && length $passwd ){
				my $server = $dbms->{config}{name}."\\".$instance;
				# SQLServer 2008R2 doesn't like have a server connection string with MSSQLSERVER default instance
				$server = undef if $instance eq "MSSQLSERVER";
				Mods::Toops::msgVerbose( "SqlServer::_connect() calling sql_init with server='".( $server || '(undef)' )."', account='$account'..." );
				$sqlsrv = Win32::SqlServer::sql_init( $server, $account, $passwd );
				Mods::Toops::msgVerbose( "SqlServer::_connect() sqlsrv->isconnected()=".$sqlsrv->isconnected());
				#print Dumper( $sqlsrv );
				if( $sqlsrv && $sqlsrv->isconnected()){
					$sqlsrv->{ErrInfo}{MaxSeverity} = 17;
					$sqlsrv->{ErrInfo}{SaveMessages} = 1;
					Mods::Toops::msgVerbose( "SqlServer::_connect() successfully connected" );
					$dbms->{instance}{sqlsrv} = $sqlsrv;
				} else {
					Mods::Toops::msgErr( "SqlServer::_connect() unable to connect to '$instance' instance" );
					$sqlsrv = undef;
				}
			} else {
				Mods::Toops::msgErr( "SqlServer::_connect() unable to get account/password couple" );
			}
		} else {
			Mods::Toops::msgErr( "SqlServer::_connect() instance is mandatory, not specified" );
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
		Mods::Toops::msgVerbose( "SqlServer::_getCredentials() got account='".( $account || '(undef)' )."'" );
	} else {
		Mods::Toops::msgErr( "SqlServer::_getCredentials() instance is mandatory, not specified" );
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
		$result = Mods::SqlServer::_sqlNoResult( $dbms, $parms );
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
	Mods::Toops::msgVerbose( "SqlServer::_restoreDatabaseFile() restoring $fname" );
	my $sqlsrv = _connect( $dbms );
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = _restoreDatabaseMove( $dbms, $parms );
	my $result = undef;
	if( $move ){
		$parms->{'sql'} = "RESTORE DATABASE $database FROM DISK='$fname' WITH $recovery, $move;";
		$result = Mods::SqlServer::_sqlNoResult( $dbms, $parms );
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
	my $sqlsrv = _connect( $dbms );
	my $content = $sqlsrv->sql( "RESTORE FILELISTONLY FROM DISK='$fname'" );
	my $move = undef;
	if( !scalar @{$content} ){
		Mods::Toops::msgErr( "SqlServer::_restoreDatabaseMove() unable to get the files list of the backup set" );
	} else {
		my $sqlDataPath = Mods::Toops::pathWithTrailingSeparator( $dbms->{config}{DBMSInstances}{$parms->{instance}}{dataPath} );
		foreach( @{$content} ){
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
	Mods::Toops::msgVerbose( "SqlServer::_restoreDatabaseVerify() verifying $fname" );
	my $move = _restoreDatabaseMove( $dbms, $parms );
	$parms->{'sql'} = "RESTORE VERIFYONLY FROM DISK='$fname' WITH $move;";
	return _sqlNoResult( $dbms, $parms );
}

# -------------------------------------------------------------------------------------------------
# execute a SQL request with no output
# parms is a hash ref with keys:
# - instance|sqlsrv: mandatory
# - sql: mandatory
# return true|false
sub _sqlNoResult {
	my ( $dbms, $parms ) = @_;
	Mods::Toops::msgErr( "SqlServer::_sqlNoResult() sql is mandatory, but is not specified" ) if !$parms->{sql};
	my $result = false;
	my $sqlsrv = undef;
	if( !Mods::Toops::errs()){
		$sqlsrv = Mods::SqlServer::_connect( $dbms );
	}
	if( !Mods::Toops::errs()){
		Mods::Toops::msgVerbose( "SqlServer::_sqlNoResult() executing '$parms->{sql}'" );
		$result = Mods::Toops::msgDummy( $parms->{sql} );
		if( !Mods::Toops::wantsDummy()){
			my $merged = capture_merged { $sqlsrv->sql( $parms->{sql}, Win32::SqlServer::NORESULT )};
			my @merged = split( /[\r\n]/, $merged );
			foreach my $line ( @merged ){
				chomp( $line );
				$line =~ s/^\s*//;
				$line =~ s/\s*$//;
				print " $line".EOL if length $line;
			}
			$result = $sqlsrv->sql_has_errors() ? false : true;
			delete $sqlsrv->{ErrInfo}{Messages};
		}
	}
	Mods::Toops::msgVerbose( "SqlServer::_sqlNoResult() returns '".( $result ? 'true':'false' )."'" );
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
		$res = Mods::SqlServer::_sqlNoResult( $parms );
	}
	return $res;
}

=cut

1;
