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
#     is is addressed by logsRootDir()
#     this package takes care of creating it if it doesn't exist yet

package Mods::Path;

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Path qw( make_path );
use File::Spec;
use Sys::Hostname qw( hostname );
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Toops;

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
	my $dir = Mods::Toops::var([ 'dbms', 'archivesDir' ]);
	if( defined $dir ){
		# happens that \\ftpback-xx OVH backup storage spaces are sometimes unavailable during the day
		# at least do not try to test them each time we need this address
		#makeDirExist( $dir );
	} else {
		Mods::Toops::msgWarn( "'archivesDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the current DBMS archives root tree, making sure the dir exists
# the dir can be defined in toops.json, or overriden in host configuration
sub dbmsArchivesRoot {
	my $dir = Mods::Toops::var([ 'dbms', 'archivesRoot' ]);
	if( defined $dir ){
		# happens that \\ftpback-xx OVH backup storage spaces are sometimes unavailable during the day
		# at least do not try to test them each time we need this address
		#makeDirExist( $dir );
	} else {
		Mods::Toops::msgWarn( "'archivesRoot' is not defined in toops.json nor in host configuration" );
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
	my $dir = Mods::Toops::var( [ 'dbms', 'backupsDir' ], $opts );
	if( defined $dir ){
		makeDirExist( $dir );
	} else {
		Mods::Toops::msgWarn( "'backupsDir' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# the root the the DBMS backups directories, making sure the dir exists
# the root can be defined in toops.json, or overriden in host configuration
sub dbmsBackupsRoot {
	my $dir = Mods::Toops::var([ 'dbms', 'backupsRoot' ]);
	if( defined $dir ){
		makeDirExist( $dir );
	} else {
		Mods::Toops::msgWarn( "'backupsRoot' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
# (O):
# the (maybe daily) execution reports directory
sub execReportsDir {
	my ( $opts ) = @_;
	$opts //= {};
	my $dir = Mods::Toops::var( [ 'execReports' ], $opts );
	if( defined $dir ){
		makeDirExist( $dir );
	} else {
		Mods::Toops::msgWarn( "'execReports' is not defined in toops.json nor in host configuration" );
	}
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - optionally a hostname, defaulting to the current host
#   remind that Unix has case sensitive filesystems, while Windows has not - we do not modify here the case
# (O):
# returns the full path of the host configuration file
sub hostConfigurationPath {
	my ( $host ) = @_;
	$host = hostname if !$host;
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
# (O):
# returns the root of the logs tree
# this is an optional value read from toops.json, defaulting to user temp directory, itself defaulting to /tmp (or C:\Temp)
# Though TheToolsProject doesn't force that, we encourage to have a by-daya logs tree. Thus logsRoot is the top of the
# logs hierarchy while logsDailyDir is the logs of the day (which may be the same by the fact and this is a decision of
# the site integrator)
sub logsDailyDir {
	my $dir;
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{toops}{logsDir} )){
		$dir = $TTPVars->{config}{toops}{logsDir};
	} else {
		$dir = File::Spec->catdir( logsRootDir(), 'Toops', 'logs' );
	}
	makeDirExist( $dir );
	return $dir;
}

# ------------------------------------------------------------------------------------------------
# (O):
# returns the root of the logs tree, maiking sure it exists
# this is an optional value read from toops.json, defaulting to user temp directory, itself defaulting to /tmp (or C:\Temp)
# Though TheToolsProject doesn't force that, we encourage to have a by-daya logs tree. Thus logsRoot is the top of the
# logs hierarchy while logsDailyDir is the logs of the day (which may be the same by the fact and this is a decision of
# the site integrator)
sub logsRootDir {
	my $dir;
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{toops}{logsRoot} )){
		$dir = $TTPVars->{config}{toops}{logsRoot};
	} elsif( $ENV{TEMP} ){
		$dir = $ENV{TEMP};
	} elsif( $ENV{TMP} ){
		$dir = $ENV{TMP};
	} else {
		$dir = $TTPVars->{Toops}{defaults}{$Config{osname}}{tempDir};
	}
	makeDirExist( $dir );
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
# note that this does NOT honor the '-dummy' option as creating a directory is easy and a work may blocked without that
# returns true|false
sub makeDirExist {
	my ( $dir ) = @_;
	my $result = false;
	if( -d $dir ){
		Mods::Toops::msgVerbose( "Path::makeDirExist() dir='$dir' exists" );
		$result = true;
	} else {
		Mods::Toops::msgVerbose( "Path::makeDirExist() make_path() dir='$dir'" );
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
					Mods::Toops::msgErr( $message );
				} else {
					Mods::Toops::msgErr( "$file: $message" );
				}
			}
			$result = false;
		}
		Mods::Toops::msgVerbose( "Path::makeDirExist() dir='$dir' result=$result" );
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
sub siteConfigurationsDir {
	return $ENV{TTP_CONFDIR};
}

# ------------------------------------------------------------------------------------------------
sub toopsConfigurationPath {
	return File::Spec->catdir( siteConfigurationsDir(), "toops.json" );
}

1;
