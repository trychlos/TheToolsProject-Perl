#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the json alert files dropped in the alerts dir
#
# Command-line arguments:
# - the full path to the JSON configuration file
#
# Makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;

use Data::Dumper;

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

# -------------------------------------------------------------------------------------------------
# new execution reports
# we are tracking backup databases with dbms.pl backup -nodummy
# warning when we have a diff without a previous full
sub doWithNew {
	my ( @newFiles ) = @_;
	foreach my $file ( @newFiles ){
		Mods::Toops::msgVerbose( "new alert '$file'" );
		my $data = Mods::Toops::jsonRead( $file );
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
