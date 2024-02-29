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
use File::Find;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Path;
use Mods::Toops;

# auto-flush on socket
$| = 1;

my $commands = {
	#help => \&help,
};

my $daemon = Mods::Daemon::daemonInitToops( $0, \@ARGV );
my $TTPVars = Mods::Toops::TTPVars();

# scanning for new elements
my $lastScanTime = 0;
my $first = true;
my @previousScan = ();
my @runningScan = ();

# -------------------------------------------------------------------------------------------------
# new alert
# should never arrive as all alerts must be sent through MQTT bus
sub doWithNew {
	my ( @newFiles ) = @_;
	foreach my $file ( @newFiles ){
		Mods::Message::msgVerbose( "new alert '$file'" );
		my $data = Mods::Toops::jsonRead( $file );
	}
}

# -------------------------------------------------------------------------------------------------
# we find less files in this iteration than in the previous - maybe some files have been purged, deleted
# moved, or we have a new directory, or another reason - just reset and restart over
sub varReset {
	Mods::Message::msgVerbose( "varReset()" );
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
	@runningScan = ();
	find( \&wanted, $daemon->{config}{monitoredDir} );
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
# - the daemon configuration must have monitoredDir key
if( scalar @ARGV != 1 ){
	Mods::Message::msgErr( "not enough arguments, expected <json>, found ".join( ' ', @ARGV )); 
} else {
	if( exists( $daemon->{config}{monitoredDir} )){
		Mods::Message::msgVerbose( "monitored dir '$daemon->{config}{monitoredDir}' successfully found in daemon configuration file" );
	} else {
		Mods::Message::msgErr( "'monitoredDir' must be specified in daemon configuration, not found" );
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

Mods::Message::msgVerbose( "sleepTime='$sleepTime'" );
Mods::Message::msgVerbose( "scanInterval='$scanInterval'" );

while( !$daemon->{terminating} ){
	my $res = Mods::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	if( $now - $lastScanTime >= $scanInterval ){
		works();
		$lastScanTime = $now;
	}
	sleep( $sleepTime );
}

Mods::Daemon::terminate( $daemon );
