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
# - the service to be monitored for backups
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

my $daemon = Mods::Daemon::daemonInitToops( $0, \@ARGV, { add => $ARGV[2] || undef });
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
sub _execReport {
	my ( $report ) = @_;
	Mods::Toops::execReportAppend( $report );
	push( @{$stats->{restored}}, $report );
}

# -------------------------------------------------------------------------------------------------
# evaluate macros
# REMOTESHARE
# REMOTEHOST
# (I);
# - a string
# (O):
# - same thing, with macros having been replaced
sub _evaluate {
	my ( $str ) = @_;
	$str =~ s/<REMOTESHARE>/$daemon->{monitored}{config}{remoteShare}/;
	$str =~ s/<REMOTEHOST>/$daemon->{monitored}{config}{name}/;
	return $str;
}

# -------------------------------------------------------------------------------------------------
# evaluate an array of strings
# (I);
# - an array of strings
# (O):
# - an array, with macros having been replaced
sub _evaluateArray {
	my @res = ();
	foreach my $it ( @_ ){
		push( @res, _evaluate( $it ));
	}
	return @res;
}

# -------------------------------------------------------------------------------------------------
# happens that there are lot of situations where we will not be able to keep in memory the last full backup of a database
# the first of these being the case where the daemon is restarted after a full backup has occured.
# it we do not do something, it will not be able to restore anything until another full backup pass here..
# we have two options:
# - search locally for the last full backup
# - or search remotely
# Returns true if we have found (and made available) the last full backup, or false if we must give up
my $searchForLastFull_data = {};

sub searchForLastFull {
	my ( $report, $content ) = @_;
	my $res = false;

	# search locally, based on TTP configuration
	# hardcoding the expected format file name as host-instance-database ... -mode.backup
	# this should be enough in most situations
	my $dir = $daemon->{config}{localDir};
	$searchForLastFull_data = {};
	$searchForLastFull_data->{host} = $content->{host};
	$searchForLastFull_data->{instance} = $content->{instance};
	$searchForLastFull_data->{database} = $content->{database};
	$searchForLastFull_data->{found} = [];
	find( \&searchForLastFull_wanted, $dir );
	if( scalar @{$searchForLastFull_data->{found}} ){
		my @candidates = sort @{$searchForLastFull_data->{found}};
		my $better = pop( @candidates );
		Mods::Toops::msgVerbose( "found candidate for full backup '$better'" );
		$full->{$content->{instance}}{$content->{database}} = $better;
		$res = true;
	}
	if( !$res ){
		Mods::Toops::msgLog( "CAUTION: unable to locally find a full backup for host='$content->{host}' instance='$content->{instance}' database='$content->{database}'" );
	}

	return $res;
}

sub searchForLastFull_wanted {
	return unless /^$searchForLastFull_data->{host}-$searchForLastFull_data->{instance}-$searchForLastFull_data->{database}-[0-9]{6,6}-[0-9]{6,6}-full\.backup$/;
	push( @{$searchForLastFull_data->{found}}, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# source file is file on the source host, specified in the source language (aka a local path rather than a network path)
# we want here:
# - copy the remote file on the local host
# - returns the local path
sub syncedPath {
	my ( $report, $sourceLocal ) = @_;
	#print "report='$report'".EOL;
	#print "sourceLocal='$sourceLocal'".EOL;
	my ( $rep_volume, $rep_directories, $rep_file ) = File::Spec->splitpath( $report );
	my ( $bck_volume, $bck_directories, $bck_file ) = File::Spec->splitpath( $sourceLocal );
	my $sourceNet = File::Spec->catpath( $rep_volume, $bck_directories, $bck_file );
	#print "sourceNet='$sourceNet'".EOL;
	my $localTarget = undef;
	if( ! -r $sourceNet ){
		Mods::Toops::msgWarn( "$sourceNet: file not found or not readable" );
	} else {
		my $localDir = _evaluate( $daemon->{config}{localDir} );
		$localTarget =  File::Spec->catpath( Mods::Toops::pathWithTrailingSeparator( $localDir ), $bck_file );
		#print "localTarget='$localTarget'".EOL;
		Mods::Path::makeDirExist( $localDir );
		my $res = copy( $sourceNet, $localTarget );
		if( $res ){
			Mods::Toops::msgVerbose( "successfully copied '$sourceNet' to '$localTarget'" );
		} else {
			Mods::Toops::msgVerbose( "unable to copy '$sourceNet' to '$localTarget'" );
			$localTarget = undef;
		}
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
			if( $instance ne $daemon->{monitored}{config}{Services}{$daemon->{monitored}{service}}{instance} ){
				Mods::Toops::msgVerbose( "instance='$instance' ignored" );
				$stats->{ignored} += 1;
				next;
			}

			my $database = $data->{database};
			if( !grep ( /$database/, @{$daemon->{monitored}{config}{Services}{$daemon->{monitored}{service}}{databases}} )){
				Mods::Toops::msgVerbose( "database='$database' ignored" );
				$stats->{ignored} += 1;
				next;
			}

			my $mode = $data->{mode};
			my $output = $data->{output};

			my $executable = true;
			my $candidates = [];
			my $local = undef;
			$candidates = $daemon->{config}{databases} if exists $daemon->{config}{databases};
			if( scalar @{$candidates} && !grep( /$database/i, @{$candidates} )){
				Mods::Toops::msgVerbose( "backuped database is '$database' while configured are [".join( ', ', @{$candidates} )."]: ignored" );
				$executable = false;
			} else {
				# transfert the remote backup file to our backup host, getting the local backup file (from remote host) to be restored
				$local = syncedPath( $report, $output );
				if( $local ){
					if( $mode eq "full" ){
						$full->{$instance}{$database} = $local;
					} elsif( $mode eq "diff" ){
						if( !exists( $full->{$instance}{$database} ) || !$full->{$instance}{$database} || !length( $full->{$instance}{$database} )){
							Mods::Toops::msgWarn( "host='$data->{host}' instance='$instance' database='$database' found diff backup, but no previous full is recorded" );
							$executable = searchForLastFull( $report, $data );
						}
					} else {
						Mods::Toops::msgErr( "host='$data->{host}' instance='$instance' database='$database' mode='$mode': mode is unknown" );
						$executable = false;
					}
				} else {
					$executable = false;
				}
			}
			if( $executable ){
				my $restoreInstance = $instance;
				$restoreInstance = $daemon->{config}{restoreInstance} if exists $daemon->{config}{restoreInstance} && length $daemon->{config}{restoreInstance};
				my $command = "dbms.pl restore -instance $restoreInstance -database $database ";
				if( $mode eq "full" ){
					$command .= " -full $local";
				} else {
					$command .= " -full $full->{$instance}{$database} -diff $local";
				}
				Mods::Toops::msgVerbose( "executing $command" );
				my $out = `$command`;
				print $out;
				Mods::Toops::msgLog( $out );
				_execReport({
					reportSourceFileName => $report,
					reportData => $data,
					localSynced => $local,
					command => $command,
					now => localtime->strftime( "%Y-%m-%d %H:%M%S" )
				});
			} else {
				$stats->{ignored} += 1;
			}

		} else {
			$stats->{ignored} += 1;
			Mods::Toops::msgVerbose( "not a non-dummy database backup, ignored" );
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
	# update the service informations too
	$daemon->{monitored}{config} = Mods::Toops::evaluate( $daemon->{monitored}{config} );
	# and scan..
	my @monitored = _evaluateArray( @{$daemon->{config}{monitoredDirs}} );
	if( scalar @monitored ){
		@runningScan = ();
		find( \&wanted, @monitored );
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
	} else {
		Mods::Toops::msgWarn( "seems that 'monitoredDirs' configuration is empty" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

# first check arguments
# - monitored host must have a json configuration file
if( scalar @ARGV != 3 ){
	Mods::Toops::msgErr( "not enough arguments, expected <json> <host> <service>, found ".join( ' ', @ARGV )); 
} else {
	$daemon->{monitored}{host} = $ARGV[1];
	$daemon->{monitored}{service} = $ARGV[2];
	$daemon->{monitored}{config} = Mods::Toops::getHostConfig( $daemon->{monitored}{host} );
	if( !exists( $daemon->{monitored}{config}->{Services}{$daemon->{monitored}{service}} )){
		Mods::Toops::msgErr( "service '$daemon->{monitored}{service}' is unknown in '$daemon->{monitored}{host}' host configuration" );
	}
}
if( !Mods::Toops::errs()){
	my $scanInterval = 10;
	$scanInterval = $daemon->{config}{scanInterval} if exists $daemon->{config}{scanInterval} && $daemon->{config}{scanInterval} >= $scanInterval;

	my $sleepTime = Mods::Daemon::getSleepTime(
		$daemon->{listenInterval},
		$scanInterval
	);
	Mods::Toops::msgVerbose( "listening on port $daemon->{config}{listeningPort}" );
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

	Mods::Toops::msgLog( "terminating" );
}

Mods::Toops::ttpExit();
