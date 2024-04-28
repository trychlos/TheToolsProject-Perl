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
# A package dediccated to Microsoft SQL-Server

package TTP::SqlServer;

use strict;
use warnings;

use Capture::Tiny qw( :all );
use Data::Dumper;
use File::Spec;
use Path::Tiny;
use Time::Piece;
use Win32::SqlServer qw( :DEFAULT :consts );

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );
use TTP::Path;

my $Const = {
	# the list of system databases to be excluded
	systemDatabases => [
		'master',
		'tempdb',
		'model',
		'msdb'
	],
	# the list of system tables to be excluded
	systemTables => [
		'dtproperties',
		'sysdiagrams'
	]
};

# -------------------------------------------------------------------------------------------------
# Backup a database
# (I):
# - parms is a hash ref with following keys:
#   > database: mandatory
#   > output: optional
#   > mode: full-diff, defaulting to 'full'
#   > compress: true|false
# (O):
# - returns a hash with following keys:
#   > ok: true|false
#   > stdout: a copy of lines outputed on stdout as an array ref

sub apiBackupDatabase {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false };
	msgErr( __PACKAGE__."::apiBackupDatabase() database is mandatory, but is not specified" ) if !$parms->{database};
	msgErr( __PACKAGE__."::apiBackupDatabase() mode must be 'full' or 'diff', found '$parms->{mode}'" ) if $parms->{mode} ne 'full' && $parms->{mode} ne 'diff';
	msgErr( __PACKAGE__."::apiBackupDatabase() output is mandatory, but is not specified" ) if !$parms->{output};
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::apiBackupDatabase() entering with instance='".$dbms->instance()."' database='$parms->{database}' mode='$parms->{mode}'..." );
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
		msgVerbose( __PACKAGE__."::apiBackupDatabase() sql='$parms->{sql}'" );
		$result = _sqlExec( $dbms, $parms->{sql} );
	}
	msgVerbose( __PACKAGE__."::apiBackupDatabase() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# get and returns the list of databases in the instance
# (I):
# - the DBMS instance
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines

sub apiGetInstanceDatabases {
	my ( $me, $dbms ) = @_;
	my $result = { ok => false, output => [] };
	msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() entering with instance='".$dbms->instance()."'" );
	$result = _sqlExec( $dbms, "select name from master.sys.databases order by name" );
	if( $result->{ok} ){
		foreach( @{$result->{result}} ){
			my $dbname = $_->{'name'};
			if( !grep( /^$dbname$/, @{$Const->{systemDatabases}} )){
				push( @{$result->{output}}, $dbname );
			}
		}
		msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() found ".scalar @{$result->{output}}." databases" );
	}
	msgVerbose( __PACKAGE__."::apiGetInstanceDatabases() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# returns the list of tables in the database
# (I):
# - a parms hash with following keys:
#   > database: the database name
# (O):
# returns a hash with following keys:
# - ok: true|false
# - output: a ref to an array of output lines

sub apiGetDatabaseTables {
	my ( $me, $dbms, $parms ) = @_;
	my $result = { ok => false, output => [] };
	if( $parms->{database} ){
		msgVerbose( __PACKAGE__."::apiGetDatabaseTables() entering with instance='".$dbms->instance()."', database='$parms->{database}'" );
		$result = _sqlExec( $dbms,  "SELECT TABLE_SCHEMA,TABLE_NAME FROM $parms->{database}.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA,TABLE_NAME" );
		if( $result->{ok} ){
			foreach my $it ( @{$result->{result}} ){
				if( !grep( /^$it->{TABLE_NAME}$/, @{$Const->{systemTables}} )){
					push( @{$result->{output}}, "$it->{TABLE_SCHEMA}.$it->{TABLE_NAME}" );
				}
			}
			msgVerbose( __PACKAGE__."::apiGetDatabaseTables() found ".scalar @{$result->{output}}." tables" );
		}
	} else {
		msgErr( __PACKAGE__."::apiGetDatabaseTables() database is mandatory, but not specified" );
	}
	msgVerbose( __PACKAGE__."::apiGetDatabaseTables() result='".( $result->{ok} ? 'true' : 'false' )."'" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# get a connection to a local SqlServer instance
# (I):
# - the DBMS instance
# (O):
# - an opaque handle on the connection, or undef

sub _connect {
	my ( $dbms ) = @_;
	$dbms->{_sqlserver} //= {};
	my $sqlsrv = $dbms->{_sqlserver}{sqlsrv};
	if( $sqlsrv ){
		msgVerbose( __PACKAGE__."::_connect() instance already connected" );
	} else {
		my $instance = $dbms->instance();
		Win32::SqlServer::SetDefaultForEncryption( 'Optional', true );
		my( $account, $passwd ) = _getCredentials( $dbms );
		if( length $account && length $passwd ){
			my $server = $dbms->ttp()->node()->name()."\\".$instance;
			# SQLServer 2008R2 doesn't like have a server connection string with MSSQLSERVER default instance
			$server = undef if $instance eq "MSSQLSERVER";
			msgVerbose( __PACKAGE__."::_connect() calling sql_init with server='".( $server || '(undef)' )."', account='$account'..." );
			$sqlsrv = Win32::SqlServer::sql_init( $server, $account, $passwd );
			msgVerbose( __PACKAGE__."::_connect() sqlsrv->isconnected()=".$sqlsrv->isconnected());
			#print Dumper( $sqlsrv );
			if( $sqlsrv && $sqlsrv->isconnected()){
				$sqlsrv->{ErrInfo}{MaxSeverity} = 17;
				$sqlsrv->{ErrInfo}{SaveMessages} = 1;
				msgVerbose( __PACKAGE__."::_connect() successfully connected" );
				$dbms->{_sqlserver}{sqlsrv} = $sqlsrv;
			} else {
				msgErr( __PACKAGE__."::_connect() unable to connect to '$instance' instance" );
				$sqlsrv = undef;
			}
		} else {
			msgErr( __PACKAGE__."::_connect() unable to get account/password couple" );
		}
	}
	return $sqlsrv;
}

# ------------------------------------------------------------------------------------------------
# returns the first account defined for the named instance
# (I):
# - the DBMS instance
# (O):
# - an array ( username, password )

sub _getCredentials {
	my ( $dbms ) = @_;
	my $credentials = TTP::Credentials::get([ 'DBMS', $dbms->instance(), ]);
	my $account = undef;
	my $passwd = undef;
	if( $credentials ){
		$account = ( keys %{$credentials} )[0];
		$passwd = $credentials->{$account};
		msgVerbose( __PACKAGE__."::_getCredentials() got account='".( $account || '(undef)' )."'" );
	} else {
		msgErr( __PACKAGE__."::_getCredentials() unable to get credentials with provided arguments" );
	}
	return ( $account, $passwd );
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
	msgErr( __PACKAGE__."::_sqlExec() sql is mandatory, but is not specified" ) if !$sql;
	my $result = { ok => false, stdout => [] };
	my $sqlsrv = undef;
	if( !TTP::errs()){
		$sqlsrv = _connect( $dbms );
	}
	if( !TTP::errs()){
		msgVerbose( __PACKAGE__."::_sqlExec() executing '$sql'" );
		if( $dbms->ttp()->runner()->dummy()){
			msgDummy( $sql );
			$result->{ok} = true;
		} else {
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
	msgVerbose( __PACKAGE__."::_sqlExec() returns '".( $result->{ok} ? 'true':'false' )."'" );
	return $result;
}

1;

__END__
