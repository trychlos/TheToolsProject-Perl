#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the backups in the live production
#
# Command-line arguments:
# - the full path to the JSON configuration file
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;

use Data::Dumper;
use File::Find;
use File::stat;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Toops;

# auto-flush on socket
$| = 1;

my $commands = {
	#help => \&help,
};

Mods::Daemon::daemonInitToops( $0 );
my $TTPVars = Mods::Toops::TTPVars();
my $daemonConfig = Mods::Daemon::getConfigByPath( $ARGV[0] );
my $socket = Mods::Daemon::daemonCreateListeningSocket( $daemonConfig );

my $lastScanTime = 0;
my $first = true;
my @previousScan = ();
my @runningScan = ();

# store here the last found full database backup
my $full = {};

# -------------------------------------------------------------------------------------------------
# new execution reports
# we are tracking backup databases with dbms.pl backup -nodummy
# warning when we have a diff without a previous full
sub doWithNew {
	my ( @newFiles ) = @_;
	foreach my $report ( @newFiles ){
		Mods::Toops::msgVerbose( "new report '$report'" );
		my $data = Mods::Toops::jsonRead( $report );
		if( exists( $data->{command} ) && $data->{command} eq "dbms.pl" && exists( $data->{verb} ) && $data->{verb} eq "backup" && ( !exists( $data->{dummy} ) || !$data->{dummy} )){

			my $instance = $data->{instance};
			my $database = $data->{database};
			my $mode = $data->{mode};
			my $output = $data->{output};

			if( $mode eq "full" ){
				$full->{$instance}{$database} = $output;
			}
			my $executable = true;
			if( $mode eq "diff" ){
				if( !exists( $full->{$instance}{$database} )){
					Mods::Toops::msgWarn( "host='$data->{host}' instance='$instance' database='$database' found diff backup, but no previous full" );
					$executable = false;
				}
			}
			my $candidates = [];
			$candidates = $daemonConfig->{databases} if exists $daemonConfig->{databases};
			if( scalar @{$candidates} && !grep( /$database/i, @{$candidates} )){
				Mods::Toops::msgVerbose( "backuped database is '$database' while configured are [".join( ', ', @{$candidates} )."]: ignored" );
				$executable = false;
			}
			if( $executable ){
				my $restoreInstance = $instance;
				$restoreInstance = $daemonConfig->{restoreInstance} if exists $daemonConfig->{restoreInstance};
				my $command = "dbms.pl restore -instance $restoreInstance -database $database -full $full->{$instance}{$database}";
				if( $mode eq "diff" ){
					$command .= " -diff $data->{output}";
				}
				Mods::Toops::msgVerbose( "executing $command" );
			}

		} else {
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
sub works {
	# reevaluate the json configuration to take into account 'eval' data
	$daemonConfig = Mods::Daemon::getConfigByPath( $ARGV[0] );
	my $monitored = $daemonConfig->{monitoredDirs};
	@runningScan = ();
	find( \&wanted, @{$monitored} );
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

my $sleep = 2;
$sleep = $daemonConfig->{listenInterval} if exists $daemonConfig->{listenInterval} && $daemonConfig->{listenInterval} >= $sleep;

my $scanInterval = 5;
$scanInterval = $daemonConfig->{scanInterval} if exists $daemonConfig->{scanInterval} && $daemonConfig->{scanInterval} >= $scanInterval;

while( !$TTPVars->{run}{daemon}{terminating} ){
	my $res = Mods::Daemon::daemonListen( $socket, $commands );
	my $now = localtime->epoch;
	if( $now - $lastScanTime >= $scanInterval ){
		works();
	}
	$lastScanTime = $now;
	sleep( $sleep );
}

Mods::Toops::msgLog( "terminating" );
Mods::Toops::ttpExit();
