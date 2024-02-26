#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the backups done in the live production.
#
# Rationale:
# - the production "live" machine does its backup periodically, and doesn't care of anything else (it is not cooperative)
# - it is to the production "backup" machine to monitor the backups, transfert the files througgh the network, and restore them on its dataserver;
#   as it is expected to be just in waiting state, and so without anything else to do, it has this job.
# Automatic restores, a full in the morning, and diff's every 2h during the day, let us be relatively sure that it will be easiy ready in case the live stops.
#
# Command-line arguments:
# - the full path to the JSON configuration file
# - the machine to be monitored for backups
#
# Additionnally to the Daemon data structure for daemon object, we have:
# daemon
#  |
#  +- raw: the raw daemon configuration
#  +- config: the evaluated and interpreted with macros daemon configuration
#  |
#  + monitored
#     |
#     +- host: the remote hostname to be monitored, specified in the command-line (e.g. NS3232346)
#     +- raw: the raw remote host configuration
#     +- config: the evaluated remote host configuration
#
# known macros here are:
# - REMOTEHOST
# - REMOTESHARE
#
# So each daemon instance only monitors one host service.
# -------------------------------------------------------
#
# Makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;

use Data::Dumper;
use File::Copy;
use File::Find;
use File::Spec;
use File::stat;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Path;
use Mods::Toops;

# auto-flush on socket
$| = 1;

my $commands = {
	stats => \&answerStats,
};

my $daemon = Mods::Daemon::daemonInitToops( $0, \@ARGV );
my $TTPVars = Mods::Toops::TTPVars();

# scanning for new elements
my $lastScanTime = 0;
my $first = true;
my @previousScan = ();
my @runningScan = ();

# store here the last found full database backup
my $full = {};

# try to have some statistics
my $stats = {
	count => 0,
	ignored => 0,
	restored => []
};

# -------------------------------------------------------------------------------------------------
sub answerStats {
	my ( $req ) = @_;
	my $answer = "total seen execution reports: $stats->{count}".EOL;
	$answer .= "ignored: $stats->{ignored}".EOL;
	my $executed = scalar @{$stats->{restored}};
	$answer .= "restore operations: $executed".EOL;
	if( $executed ){
		my $last = @{$stats->{restored}}[$executed-1];
		$answer .= "last was from $last->{reportSourceFileName} to $last->{localSynced} at $stats->{now}".EOL;
	}
	$answer .= "OK".EOL;
	return $answer;
}

# -------------------------------------------------------------------------------------------------
#  all needed dynamic variables are computed here at the very beginning of each scan loop
# - reevaluate the remote host configuration
# - interpret macros in daemon configuration:
#   > REMOTESHARE
#   > REMOTEHOST
sub computeDynamics {
	# remote host configuration
	$daemon->{monitored}{config} = Mods::Toops::evaluate( $daemon->{monitored}{raw} );
	# daemon configuration is reevaluated by Daemon::daemonListen() on each listenInterval
	# we still have to substitute macros
	$daemon->{config} = computeMacrosRec( $daemon->{config} );
	# monitored dir is the (maybe daily) remote host execReportsDir
	my $dir = Mods::Path::execReportsDir({ config => $daemon->{monitored}{config} });
	my( $ler_vol, $ler_dirs, $ler_file ) = File::Spec->splitpath( $dir );
	$daemon->{dyn}{remoteExecReportsDir} = File::Spec->catpath( $daemon->{monitored}{config}{remoteShare}, $ler_dirs, $ler_file );
}

# -------------------------------------------------------------------------------------------------
sub computeMacrosRec {
	my ( $var ) = @_;
	my $result = $var;
	my $ref = ref( $var );
	if( $ref eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$var} ){
			$result->{$key} = computeMacrosRec( $var->{$key} );
		}
	} elsif( $ref eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$var} ){
			push( @{$result}, computeMacrosRec( $it ));
		}
	} elsif( !$ref ){
		$result =~ s/<REMOTEHOST>/$daemon->{monitored}{host}/g;
		$result =~ s/<REMOTESHARE>/$daemon->{monitored}{config}{remoteShare}/g;
	}
	#Mods::Toops::msgVerbose( "var='$var' ref='$ref' result='$result'" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
sub _execReport {
	my ( $report ) = @_;
	Mods::Toops::execReportAppend( $report );
	push( @{$stats->{restored}}, $report );
}

# -------------------------------------------------------------------------------------------------
# (I):
# - backup report to be restored
# (O):
# returns a hash with following keys:
# - full: always, the (local) full backup to be restored
# - diff: if set, the (local) diff backup to be restored
# or undef in case of an error
sub locallySyncedBackups {
	my ( $report ) = @_;
	my $result = undef;

	my $localTarget = syncedPath( $report->{output} );
	return false if !$localTarget;

	# if we are about to restore a full backup, then we are finished here
	# else, in order to be able to restore a diff backup, we have to also got the last full
	# happens that there are lot of situations where we will not be able to keep in memory the last full backup of a database
	# the first of these being the case where the daemon is restarted after a full backup has occured.
	# it we do not do something, it will not be able to restore anything until another full backup pass here..
	if( $report->{mode} eq "full" ){
		$result = { full => $localTarget };
		$full->{$report->{instance}}{$report->{database}} = $localTarget;

	} else {
		$result = { diff => $localTarget };
		$result->{full} = undef;
		# we can search for the last full in the global 'full' hash which is expected to remember this sort of thing,
		# or in the localDir, or remotely by examining execReports dir...
		# -> first thing: do we remember the last full ?
		if( exists( $full->{$report->{instance}}{$report->{database}} )){
			$result->{full} = $full->{$report->{instance}}{$report->{database}};
			Mods::Toops::msgVerbose( "found last full as remembered '$full->{$report->{instance}}{$report->{database}}'" );
		} else {
			# -> second: try to search in the localDir, hoping that the file has the old-classic name
			my $lastfull = locallySearchLastFull( $report );
			if( $lastfull ){
				$full->{$report->{instance}}{$report->{database}} = $lastfull;
				$result->{full} = $lastfull;
				Mods::Toops::msgVerbose( "found last full as local '$lastfull'" );
			} else {
				# -> last chance it to scan remote execution reports
				$lastfull = remoteSearchLastFull( $report );
				if( $lastfull ){
					$full->{$report->{instance}}{$report->{database}} = $lastfull;
					$result->{full} = $lastfull;
					Mods::Toops::msgVerbose( "found remote last full, transferred to '$lastfull'" );
				}
			}
		}
	}

	return $result;
}

# -------------------------------------------------------------------------------------------------
# search locally for the last full backup
# Returns the path to the local backup if we have found it
my $_localdata = {};

sub locallySearchLastFull {
	my ( $report ) = @_;
	my $res = undef;
	# search locally, based on TTP configuration
	# hardcoding the expected format file name as host-instance-database ... -mode.backup
	# this should be enough in most situations
	my $dir = $daemon->{config}{localDir};
	Mods::Toops::msgVerbose( "searching for full backup in '$dir'" );
	$_localdata = {};
	$_localdata->{host} = $report->{host};
	$_localdata->{instance} = $report->{instance};
	$_localdata->{database} = $report->{database};
	$_localdata->{found} = [];
	find( \&locallySearchLastFull_wanted, $dir );
	if( scalar @{$_localdata->{found}} ){
		my @candidates = sort @{$_localdata->{found}};
		$res = pop( @candidates );
	}
	return $res;
}

sub locallySearchLastFull_wanted {
	return unless /^$_localdata->{host}-$_localdata->{instance}-$_localdata->{database}-[0-9]{6,6}-[0-9]{6,6}-full\.backup$/;
	push( @{$_localdata->{found}}, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# search for last full backup starting by scanning remote execution reports
# return the transferred last full if possible;
my $_remote = [];
sub remoteSearchLastFull {
	my ( $report ) = @_;
	my $res = undef;
	# get the remote execution reports
	find( \&remoteSearchLastFull_wanted, $daemon->{dyn}{remoteExecReportsDir} );
	# sort in reverse name order (the most recent first)
	my @sorted = reverse sort @{$_remote};
	foreach my $json ( @sorted ){
		my $remote = Mods::Toops::jsonRead( $json );
		if( $remote->{instance} eq $report->{instance} && $remote->{database} eq $report->{database} && $remote->{mode} eq 'full' && !$remote->{dummy} ){
			$res = syncedPath( $remote->{output} );
		}
	}
	return $res;
}

sub remoteSearchLastFull_wanted {
	return unless /\.json$/;
	push( @{$_remote}, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# source file is file on the source host, specified in the source language (aka a local path rather than a network path)
# we want here:
# - copy the remote file on the local host
# - returns the local path, or undef in case of an error
sub syncedPath {
	my ( $localSource ) = @_;
	Mods::Toops::msgVerbose( "localSource='$localSource'" );
	# the output file is specified as a local filename in the remote host
	# we need to get a the remote filename (source of the copy) and the local filename (target of the copy)
	my( $rl_vol, $rl_dirs, $rl_file ) = File::Spec->splitpath( $localSource );
	my $remoteSource = File::Spec->catpath( $daemon->{monitored}{config}{remoteShare}, $rl_dirs, $rl_file );
	Mods::Toops::msgVerbose( "remoteSource='$remoteSource'" );
	# local target
	my $localTarget = Mods::Toops::pathWithTrailingSeparator( $daemon->{config}{localDir} );
	Mods::Toops::msgVerbose( "localTarget='$localTarget'" );
	Mods::Path::makeDirExist( $daemon->{config}{localDir} );
	my $res = Mods::Toops::copyFile( $remoteSource, $localTarget );
	if( $res ){
		Mods::Toops::msgVerbose( "successfully copied '$remoteSource' to '$localTarget'" );
		$localTarget = File::Spec->catpath( $localTarget, $rl_file );
	} else {
		Mods::Toops::msgErr( "unable to copy '$remoteSource' to '$localTarget': $!" );
		$localTarget = undef;
	}
	return $localTarget;
}

# -------------------------------------------------------------------------------------------------
# new execution reports
# we are tracking backup databases with dbms.pl backup -nodummy
# warning when we have a diff without a previous full
sub doWithNew {
	my ( @newFiles ) = @_;
	#print "newFiles".EOL.Dumper( @runningScan );
	foreach my $report ( @newFiles ){
		$stats->{count} += 1;
		Mods::Toops::msgVerbose( "new report '$report'" );
		my $data = Mods::Toops::jsonRead( $report );
		if( exists( $data->{command} ) && $data->{command} eq "dbms.pl" && exists( $data->{verb} ) && $data->{verb} eq "backup" && ( !exists( $data->{dummy} ) || !$data->{dummy} )){

			my $instance = $data->{instance};
			if( $instance ne $daemon->{monitored}{config}{Services}{$daemon->{config}{monitoredService}}{instance} ){
				Mods::Toops::msgVerbose( "instance='$instance' ignored" );
				$stats->{ignored} += 1;
				next;
			}

			my $database = $data->{database};
			if( !grep ( /$database/, @{$daemon->{monitored}{config}{Services}{$daemon->{config}{monitoredService}}{databases}} )){
				Mods::Toops::msgVerbose( "database='$database' ignored" );
				$stats->{ignored} += 1;
				next;
			}

			my $mode = $data->{mode};
			my $output = $data->{output};

			# have to make sure we have locally this file to be restored, plus maybe the last full backup
			# transfert the remote backup file to our backup host, getting the local backup file (from remote host) to be restored
			my $result = locallySyncedBackups( $data );
			if( $result ){
				# restore instance if the instance defined for this service in this host
				my $hostConfig = Mods::Toops::getHostConfig();
				my $restoreInstance = $hostConfig->{Services}{$daemon->{config}{monitoredService}}{instance};
				my $command = "dbms.pl restore -instance $restoreInstance -database $database ";
				$command .= " -full $result->{full}";
				$command .= " -diff $result->{diff}" if $result->{diff};
				Mods::Toops::msgVerbose( "executing $command" );
				my $out = `$command`;
				print $out;
				Mods::Toops::msgLog( $out );
			} else {
				Mods::Toops::msgWarn( "result is undefined, unable to restore" );
			}
		}
	}
}

# -------------------------------------------------------------------------------------------------
# we find less files in this iteration than in the previous - maybe some files have been purged, deleted
# moved, or we have a new directory, or another reason - just reset and restart over
sub varReset {
	Mods::Toops::msgVerbose( "varReset()" );
	@previousScan = ();
}

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.
sub wanted {
	return unless /\.json$/;
	push( @runningScan, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# do its work
# because the directories we are monitoring here are typically backups/logs directories and their
# name may change every day
sub works {
	# recompute at each loop all dynamic variables
	computeDynamics();
	# and scan..
	@runningScan = ();
	find( \&wanted, $daemon->{dyn}{remoteExecReportsDir} );
	if( scalar @runningScan < scalar @previousScan ){
		varReset();
	} elsif( $first ){
		$first = false;
		@previousScan = sort @runningScan;
	} elsif( scalar @runningScan > scalar @previousScan ){
		my @sorted = sort @runningScan;
		my @tmp = @sorted;
		my @newFiles = splice( @tmp, scalar @previousScan, scalar @runningScan - scalar @previousScan );
		doWithNew( @newFiles );
		@previousScan = @sorted;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

# first check arguments
# - monitored host must have a json configuration file
# - the daemon configuration must have monitoredService and localDir keys
if( scalar @ARGV != 2 ){
	Mods::Toops::msgErr( "not enough arguments, expected <json> <host>, found ".join( ' ', @ARGV )); 
} else {
	$daemon->{monitored}{host} = $ARGV[1];
	$daemon->{monitored}{raw} = Mods::Toops::getHostConfig( $daemon->{monitored}{host}, { withEvaluate => false });
	$daemon->{monitored}{config} = Mods::Toops::evaluate( $daemon->{monitored}{raw} );
	# daemon: monitoredService
	# set TTPVars->{run}{daemon}{add} to improve logs
	if( exists( $daemon->{config}{monitoredService} )){
		if( exists( $daemon->{monitored}{config}{Services}{$daemon->{config}{monitoredService}} )){
			Mods::Toops::msgVerbose( "monitored service '$daemon->{config}{monitoredService}' successfully found in remote host '$daemon->{monitored}{host}' configuration file" );
			$TTPVars->{run}{daemon}{add} = $daemon->{config}{monitoredService};
		} else {
			Mods::Toops::msgErr( "monitored service '$daemon->{config}{monitoredService}' doesn't exist in remote host '$daemon->{monitored}{host}' configuration file" );
		}
	} else {
		Mods::Toops::msgErr( "'monitoredService' must be specified in daemon configuration, not found" );
	}
	# daemon: localDir
	if( exists( $daemon->{config}{localDir} )){
		Mods::Toops::msgVerbose( "local dir '$daemon->{config}{localDir}' successfully found in daemon configuration file" );
	} else {
		Mods::Toops::msgErr( "'localDir' must be specified in daemon configuration, not found" );
	}
	# host: remoteShare
	if( exists( $daemon->{monitored}{config}{remoteShare} )){
		Mods::Toops::msgVerbose( "found remoteShare='$daemon->{monitored}{config}{remoteShare}'" );
	} else {
		Mods::Toops::msgErr( "remote share must be specified in remote host '$daemon->{monitored}{host}' configuration, not found" );
	}
}
if( Mods::Toops::errs()){
	Mods::Toops::ttpExit();
}

my $scanInterval = 10;
$scanInterval = $daemon->{config}{scanInterval} if exists $daemon->{config}{scanInterval} && $daemon->{config}{scanInterval} >= $scanInterval;

my $sleepTime = Mods::Daemon::getSleepTime(
	$daemon->{listenInterval},
	$scanInterval
);

Mods::Toops::msgVerbose( "sleepTime='$sleepTime'" );
Mods::Toops::msgVerbose( "scanInterval='$scanInterval'" );

while( !$daemon->{terminating} ){
	my $res = Mods::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	#print "now=$now lastScanTime=$lastScanTime now-lastScanTime=".( $now - $lastScanTime)." scanInterval=$scanInterval".EOL;
	if( $now - $lastScanTime >= $scanInterval ){
		works();
		$lastScanTime = $now;
	}
	sleep( $sleepTime );
}

Mods::Daemon::terminate( $daemon );