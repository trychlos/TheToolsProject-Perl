# Copyright (@) 2023-2024 PWI Consulting
#
# Various paths management
#
# The integrator must configure:
#
# - as environment variables:
#
#   > TTP_CONFDIR: as the path to the tree which contains all configurations files, and specially 'toops.json'
#     it is suggested that this configuration tree be outside of the Toops installation
#     it is addressed by siteConfigurationsDir()
#     the structure is fixed at the moment:
#
#       TTP_CONFDIR/
#        |
#        +- toops.json
#            |
#            +- daemons/
#            |
#            +- machines/
#
# - in toops.json:
#
#   > logsRoot: the root of the logs tree
#     is is used by logsRootDir()
#     this package takes care of creating it if it doesn't exist yet

package Mods::Path;

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
# (O):
# - the (maybe daily) alerts directory
sub alertsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = Mods::Toops::var([ 'alerts', 'withFile', 'dropDir' ], $opts );
	if( defined $dir && length $dir ){
		my $makeDirExist = true;
		$makeDirExist = $opts->{makeDirExist} if exists $opts->{makeDirExist};
		makeDirExist( $dir ) if $makeDirExist;
	} else {
		msgWarn( "'alertsDir/withFile/dropDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# - the credentials directory
sub credentialsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = Mods::Toops::var([ 'credentialsDir' ], $opts );
	if( !defined $dir || !length $dir ){
		msgWarn( "'alertsDir/withFile/dropDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# returns the directory which contains the daemons configurations
# at the moment, a non-configurable subdirectory of TTP_CONFDIR
sub daemonsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "daemons" );
}

# ------------------------------------------------------------------------------------------------
# (O):
# the current DBMS archives directory, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsArchivesDir {
	my $dir = Mods::Toops::var([ 'DBMS', 'archivesDir' ]);
	if( defined $dir && length $dir ){
		# happens that \\ftpback-xx OVH backup storage spaces are sometimes unavailable during the day
		# at least do not try to test them each time we need this address
		#makeDirExist( $dir );
	} else {
		msgWarn( "'archivesDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the current DBMS archives root tree, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsArchivesRoot {
	my $dir = Mods::Toops::var([ 'DBMS', 'archivesRoot' ]);
	if( defined $dir && length $dir ){
		# happens that \\ftpback-xx OVH backup storage spaces are sometimes unavailable during the day
		# at least do not try to test them each time we need this address
		#makeDirExist( $dir );
	} else {
		msgWarn( "'archivesRoot' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
# (O):
# the current DBMS backups directory, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsBackupsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = Mods::Toops::var( [ 'DBMS', 'backupsDir' ], $opts );
	if( defined $dir && length $dir ){
		makeDirExist( $dir );
	} else {
		msgWarn( "'backupsDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the root the the DBMS backups directories, making sure the dir exists
# the root can be defined in toops.json, or overriden in host configuration
sub dbmsBackupsRoot {
	my $dir = Mods::Toops::var([ 'DBMS', 'backupsRoot' ]);
	if( defined $dir && length $dir ){
		makeDirExist( $dir );
	} else {
		msgWarn( "'backupsRoot' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
# (O):
# - the (maybe daily) execution reports directory
sub execReportsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = Mods::Toops::var([ 'executionReports', 'withFile', 'dropDir' ], $opts );
	if( defined $dir && length $dir ){
		my $makeDirExist = true;
		$makeDirExist = $opts->{makeDirExist} if exists $opts->{makeDirExist};
		makeDirExist( $dir ) if $makeDirExist;
	} else {
		msgWarn( "'executionReports/withFile/dropDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# returns the path requested by the given command
# (I):
# - the command to be executed
# - an optional options hash with following keys:
#   > mustExists, defaulting to false
# ((O):
# - returns a path of undef if an error has occured
sub fromCommand {
	my( $cmd, $opts ) = @_;
	$opts //= {};
	msgErr( "Path::fromCommand() command is not specified" ) if !$cmd;
	my $path = undef;
	if( !Mods::Toops::errs()){
		$path = `$cmd`;
		msgErr( "Path::fromCommand() command doesn't output anything" ) if !$path;
	}
	if( !Mods::Toops::errs()){
		my @words = split( /\s+/, $path );
		if( scalar @words < 2 ){
			msgErr( "Path::fromCommand() expect at least two words" );
		} else {
			$path = $words[scalar @words - 1];
			msgErr( "Path::fromCommand() found an empty path" ) if !$path;
		}
	}
	if( !Mods::Toops::errs()){
		my $mustExists = false;
		$mustExists = $opts->{mustExists} if exists $opts->{mustExists};
		if( $mustExists && !-r $path ){
			msgErr( "Path::fromCommand() path='$path' doesn't exist or is not readable" );
			$path = undef;
		}
	}
	$path = undef if Mods::Toops::errs();
	return $path;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - optionally a hostname, defaulting to the current host
#   remind that Unix has case sensitive filesystems, while Windows has not - we do not modify here the case
# (O):
# returns the full path of the host configuration file
sub hostConfigurationPath {
	my ( $host ) = @_;
	$host = Mods::Toops::_hostname() if !$host;
	return File::Spec->catdir( hostsConfigurationsDir(), "$host.json" );
}

# ------------------------------------------------------------------------------------------------
# (O):
# returns the dir which contains hosts configuration files
# at the moment, a non-configurable subdirectory of TTP_CONFDIR
sub hostsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "machines" );
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
# (O):
# returns the logs tree for the day
# this is an optional value read from toops.json, defaulting to user temp directory, itself defaulting to /tmp (or C:\Temp)
# Though TheToolsProject doesn't force that, we encourage to have a by-day logs tree. Thus logsRoot is the top of the
# logs hierarchy while logsDailyDir is the logs of the day (which may be the same by the fact, and this is a decision of
# the site integrator)
sub logsDailyDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir;
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{host}{logsDir} )){
		$dir = $TTPVars->{config}{host}{logsDir};
	} elsif( exists( $TTPVars->{config}{toops}{logsDir} )){
		$dir = $TTPVars->{config}{toops}{logsDir};
	} else {
		$dir = File::Spec->catdir( logsRootDir( $opts ), 'Toops', 'logs' );
	}
	my $makeDirExist = true;
	$makeDirExist = $opts->{makeDirExist} if exists $opts->{makeDirExist};
	makeDirExist( $dir ) if $makeDirExist;
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > makeDirExist: whether to create the directory if it doesn't yet exist, defaulting to true
#     this is useful when this function is called from a to-be-evaluated json configuration file
# (O):
# returns the root of the logs tree, making sure it exists
# this is an optional value read from toops.json, defaulting to user temp directory, itself defaulting to per-OS temp directory
# Though TheToolsProject doesn't force that, we encourage to have a by-day logs tree. Thus logsRoot is the top of the
# logs hierarchy while logsDailyDir is the logs of the day (which may be the same by the fact and this is a decision of
# the site integrator)
sub logsRootDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir;
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{host}{logsRoot} )){
		$dir = $TTPVars->{config}{host}{logsRoot};
	} elsif( exists( $TTPVars->{config}{toops}{logsRoot} )){
		$dir = $TTPVars->{config}{toops}{logsRoot};
	} elsif( $ENV{TEMP} ){
		$dir = $ENV{TEMP};
	} elsif( $ENV{TMP} ){
		$dir = $ENV{TMP};
	} else {
		$dir = $TTPVars->{Toops}{defaults}{$Config{osname}}{tempDir};
	}
	my $makeDirExist = true;
	$makeDirExist = $opts->{makeDirExist} if exists $opts->{makeDirExist};
	makeDirExist( $dir ) if $makeDirExist;
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
# note that this does NOT honor the '-dummy' option as creating a directory is easy and a work may be blocked without that
# returns true|false
sub makeDirExist {
	my ( $dir ) = @_;
	my $result = false;
	if( -d $dir ){
		#msgVerbose( "Path::makeDirExist() dir='$dir' exists" );
		$result = true;
	} else {
		msgVerbose( "Path::makeDirExist() make_path() dir='$dir'" );
		my $error;
		$result = true;
		make_path( $dir, {
			verbose => Mods::Toops::TTPVars()->{run}{verbose},
			error => \$error
		});
		# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
		if( $error && @$error ){
			for my $diag ( @$error ){
				my ( $file, $message ) = %$diag;
				if( $file eq '' ){
					msgErr( $message );
				} else {
					msgErr( "$file: $message" );
				}
			}
			$result = false;
		}
		msgVerbose( "Path::makeDirExist() dir='$dir' result=$result" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing character
sub removeTrailingChar {
	my $line = shift;
	my $char = shift;
	if( substr( $line, -1 ) eq $char ){
		$line = substr( $line, 0, length( $line )-1 );
	}
	return $line;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing path separator
sub removeTrailingSeparator {
	my $dir = shift;
	my $sep = File::Spec->catdir( '' );
	return removeTrailingChar( $dir, $sep );
}

# ------------------------------------------------------------------------------------------------
sub siteConfigurationsDir {
	msgErr( "TTP_CONFDIR is not found in your environment, but is required" ) if !$ENV{TTP_CONFDIR};
	return $ENV{TTP_CONFDIR};
}

# ------------------------------------------------------------------------------------------------
sub siteRoot {
	return Mods::Toops::var( 'siteRoot' );
}

# ------------------------------------------------------------------------------------------------
sub toopsConfigurationPath {
	return File::Spec->catdir( siteConfigurationsDir(), "toops.json" );
}

# -------------------------------------------------------------------------------------------------
# Make sure we returns a path with a trailing separator
sub withTrailingSeparator {
	my $dir = shift;
	$dir = removeTrailingSeparator( $dir );
	my $sep = File::Spec->catdir( '' );
	$dir .= $sep;
	return $dir;
}

1;
