# Copyright (@) 2023-2024 PWI Consulting

package Mods::SqlServer;

use strict;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
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
sub backupDatabase {
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
				my $server = $dbms->{config}{host}."\\".$instance;
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

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
sub getDatabaseTables {
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
sub getLiveDatabases {
	my ( $me, $dbms ) = @_;
	my $result = undef;
	my $instance = $dbms->{instance}{name};
	Mods::Toops::msgVerbose( "SqlServer::getLiveDatabases() entering with instance='".$instance || '(undef)'."'" );
	if( $instance ){
		my $sqlsrv = Mods::SqlServer::_connect( $dbms );
		if( !Mods::Toops::errs() && $sqlsrv ){
			$result = [];
			my $res = $sqlsrv->sql( "SELECT name FROM master.sys.databases" );
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
# execute a SQL request with no output
# parms is a hash ref with keys:
# - instance|sqlsrv: mandatory
# - sql: mandatory
# - dummy: true|false, defaulting to false
# return true|false
sub sqlNoResult( $ ){
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
Sub::Exporter::setup_exporter({
	exports => [ qw(
		backupDatabase
		checkInstance
		computeDefaultBackup
		connect
		getBackupFilename
		getCandidatesDatabases
		getCredentials
		getInstancesCount
		listTables
		listUserDatabasesForInstance
		listUserDatabasesForSqlSrv
		restoreDatabase
		sqlNoResult
		sqlWithResult
		updateStatistics
	)]
});

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - db: mandatory
# - fname: output file
# - verbose: default to false
# return true|false
sub dumpDatabase( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $db = $parms->{'db'};
	my $fname = $parms->{'fname'};
	my $verbose = $parms->{'verbose'} || false;
	my $res = false;
	msgErr( "dumpDatabase() instance is mandatory, not specified" ) if !$instance;
	msgErr( "dumpDatabase() db is mandatory, not specified" ) if !$db;
	msgErr( "dumpDatabase() fname is mandatory, not specified" ) if !$fname;
	if( !errs()){
		my $sqlsrv = Mods::SqlServer::connect( $parms );
		$parms->{'sqlsrv'} = $sqlsrv;
		if( $sqlsrv ){
			my $tables = listTablesWithConnect( $parms );
			foreach my $table ( @{$tables} ){
				$parms->{'table'} = $table;
				Mods::SqlServer::dumpTableWithConnect( $parms );
			}
		}
	}
	msgVerbose( "backupDatabase() returns '".( $res ? 'true':'false' )."'" ) if $verbose;
	return $res;
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - sqlsrv: mandatory
# - db: mandatory, as a string
# - table: mandatory, as a hash { TABLE_SCHEMA, TABLE_NAME }
# - fname: output file
# - verbose: default to false
# return true|false
sub dumpTableWithConnect( $ ){
	my $parms = shift;
	my $sqlsrv = $parms->{'sqlsrv'};
	my $db = $parms->{'db'};
	my $table = $parms->{'table'};
	my $fname = $parms->{'fname'};
	my $verbose = $parms->{'verbose'} || false;
	msgErr( "dumpTableWithConnect() sqlsrv is mandatory, not specified" ) if !$sqlsrv;
	msgErr( "dumpTableWithConnect() db is mandatory, not specified" ) if !$db;
	msgErr( "dumpTableWithConnect() table is mandatory, not specified" ) if !$table;
	msgErr( "dumpTableWithConnect() fname is mandatory, not specified" ) if !$fname;
	my $count = 0;
	if( !errs()){
		my $res = $sqlsrv->sql( "SELECT * FROM $db.".$table->{'TABLE_SCHEMA'}.".".$table->{'TABLE_NAME'} );
	}
	return $count;
	msgVerbose( "dumpTableWithConnec() found $count rows" ) if $verbose;
	return $count;
}

# ------------------------------------------------------------------------------------------------
# returns list the list of databases for which the action is true
# + filter by the actual user databases if we are on our current host
# parms is a hash ref with keys:
# - host: default to hostname
# - instance: mandatory
# - action: mandatory
# - verbose: default to false
sub getCandidatesDatabases( $ ){
	my $parms = shift;
	my $host = $parms->{'host'} || hostname();
	my $instance = $parms->{'instance'};
	my $action = $parms->{'action'};
	my $verbose = $parms->{'verbose'} || false;
	my $list = [];
	msgErr( "getCandidatesDatabases() instance is mandatory, not specified" ) if !$instance;
	msgErr( "getCandidatesDatabases() action is mandatory, not specified" ) if !$action;
	if( !errs()){
		my $local_host = hostname();
		my $userDBs = $host eq $local_host ? Mods::SqlServer::listUserDatabasesForInstance( $parms ) : ();
		my $Refs = Mods::Constants::Refs;
		foreach( sort { lc($a) cmp lc($b) } keys %{$Refs->{$host}{$instance}{'DBs'}} ){
			if( $Refs->{$host}{$instance}{'DBs'}{$_}{$action} ){
				my $name = $_;
				if( $host ne $local_host || grep( /^$name$/, @{$userDBs} )){
					push( @{$list}, $name );
				}
			}
		}
		msgVerbose( "getCandidatesDatabases() host='$host' instance='$instance' action='$action' found ".scalar @{$list}." candidates: ".join( ',', @{$list} )) if $verbose;
	}
	return $list;
}

# ------------------------------------------------------------------------------------------------
# returns the count of instance in the current machine
sub getInstancesCount(){
	my $count = 0;
	my $host = hostname;
	$count = scalar keys %{$TTPVars->{machine_confif}{$host}{DBMSInstances}};
	msgVerbose( "getInstancesCount() on $host: found $count" );
	return $count;
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - database: mandatory
# - verbose: default to false
sub listTables( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $db = $parms->{'db'};
	my $verbose = $parms->{'verbose'} || false;
	my $list = [];
	msgErr( "listTables() instance is mandatory, not specified" ) if !$instance;
	msgErr( "listTables() db is mandatory, not specified" ) if !$db;
	if( !errs()){
		my $sqlsrv = Mods::SqlServer::connect( $parms );
		if( $sqlsrv ){
			$parms ->{'sqlsrv'} = $sqlsrv;
			$list = listTablesWithConnect( $parms );
		}
	}
	return $list;
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - verbose: default to false
sub listUserDatabasesForInstance( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $verbose = $parms->{'verbose'} || false;
	my $list = [];
	msgErr( "listUserDatabasesForInstance() instance is mandatory, not specified" ) if !$instance;
	if( !errs()){
		my $sqlsrv = Mods::SqlServer::connect( $parms );
		if( $sqlsrv ){
			$parms ->{'sqlsrv'} = $sqlsrv;
			$list = listUserDatabasesForSqlSrv( $parms );
		}
	}
	return $list;
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - sqlsrv: mandatory
# - verbose: default to false
sub listUserDatabasesForSqlSrv( $ ){
	my $parms = shift;
	my $sqlsrv = $parms->{'sqlsrv'};
	my $verbose = $parms->{'verbose'} || false;
	my $list = [];
	msgErr( "listUserDatabasesForSqlSrv() sqlsrv is mandatory, not specified" ) if !$sqlsrv;
	if( !errs()){
		my $res = $sqlsrv->sql( "SELECT name FROM master.sys.databases" );
		foreach( @{$res} ){
			my $dbname = $_->{'name'};
			if( !grep( /^$dbname$/, @{$systemDatabases} )){
				push( @{$list}, $dbname );
			}
		}
		msgVerbose( "listUserDatabasesForSqlSrv() found ".scalar @{$list}." databases: ".join( ',', @{$list} )) if $verbose;
	}
	return $list;
}

# ------------------------------------------------------------------------------------------------
# parms is a hash ref with keys:
# - instance: mandatory
# - db: mandatory
# - full: mandatory
# - diff: defaults to '' (full restore only)
# - verbose: default to false
# returns true|false
sub restoreDatabase( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $db = $parms->{'db'};
	my $full = $parms->{'full'};
	my $diff = $parms->{'diff'} || '';
	my $verbose = $parms->{'verbose'} || false;
	my $res = false;
	msgErr( "restoreDatabase() instance is mandatory, not specified" ) if !$instance;
	msgErr( "restoreDatabase() db is mandatory, not specified" ) if !$db;
	msgErr( "restoreDatabase() full is mandatory, not specified" ) if !$full;
	if( !errs()){
		my $sqlsrv = Mods::SqlServer::connect( $parms );
		if( $sqlsrv ){
			$parms->{'sqlsrv'} = $sqlsrv;
			if( _restoreDatabaseAlter( $parms )){
				$parms->{'file'} = $full;
				$parms->{'last'} = length $diff == 0 ? true : false;
				$res = _restoreDatabaseFile( $parms );
				if( $res && length $diff ){
					$parms->{'file'} = $diff;
					$parms->{'last'} = true;
					$res &= _restoreDatabaseFile( $parms ) if length $diff;
				}
			}
		}
	}
	return $res;
}

# ------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# return true|false
sub _restoreDatabaseAlter( $ ){
	my $parms = shift;
	my $db = $parms->{'db'};
	$parms->{'sql'} = "ALTER DATABASE $db SET OFFLINE WITH ROLLBACK IMMEDIATE;";
	return Mods::SqlServer::sqlNoResult( $parms );
}

# ------------------------------------------------------------------------------------------------
# restore the target database from the specified backup file
# return true|false
sub _restoreDatabaseFile( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $db = $parms->{'db'};
	my $sqlsrv = $parms->{'sqlsrv'};
	my $fname = $parms->{'file'};
	my $last = $parms->{'last'};
	my $verbose = $parms->{'verbose'} || false;
	#
	msgVerbose( "restoreDatabaseFile() restoring $fname" ) if $verbose;
	my $content = $sqlsrv->sql( "RESTORE FILELISTONLY FROM DISK='$fname'" );
	#
	my $recovery = 'NORECOVERY';
	if( $last ){
		$recovery = 'RECOVERY';
	}
	my $move = '';
	my $Refs = Mods::Constants::Refs;
	my $sqlDataPath = $Refs->{hostname()}{$instance}{'dataPath'};
	foreach( @{$content} ){
		my $row = $_;
		$move .= ', ' if length $move;
		my( $bname, $bdir, $ext ) = fileparse( $row->{'PhysicalName'}, '\.[^\.]*' );
		$move .= "MOVE '".$row->{'LogicalName'}."' TO '".$sqlDataPath.$db.( lc $ext )."'";
	}
	$parms->{'sql'} = "RESTORE DATABASE $db FROM DISK='$fname' WITH $recovery, $move;";
	return Mods::SqlServer::sqlNoResult( $parms );
}

# ------------------------------------------------------------------------------------------------
# execute a SQL request with output
# parms is a hash ref with keys:
# - instance|sqlsrv: mandatory
# - sql: mandatory
# - verbose: default to false
# return true|false
sub sqlWithResult( $ ){
	my $parms = shift;
	my $instance = $parms->{'instance'};
	my $sqlsrv = $parms->{'sqlsrv'};
	my $sql = $parms->{'sql'};
	my $verbose = $parms->{'verbose'} || false;
	msgErr( "sqlWithResult() one of instance or sqlsrv must be specified, none found" ) if !$instance && !$sqlsrv;
	msgErr( "sqlWithResult() sql is mandatory, not specified" ) if !$sql;
	my $res = false;
	if( !errs() && !$sqlsrv ){
		$sqlsrv = Mods::SqlServer::connect( $parms );
	}
	if( !errs()){
		msgVerbose( $sql ) if $verbose;
		$res = $sqlsrv->sql( $sql );
	}
	msgVerbose( "sqlWithResult() returns ".scalar( @{$res} )." rows" ) if $verbose;
	return $res;
}

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
