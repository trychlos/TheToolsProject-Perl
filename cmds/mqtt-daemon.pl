#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the published MQTT topics
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
use Net::MQTT::Simple;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Toops;

# auto-flush on socket
$| = 1;

my $commands = {
	#help => \&help,
};

my $daemon = Mods::Daemon::daemonInitToops( $0, \@ARGV );
my $TTPVars = Mods::Toops::TTPVars();

# specific to this daemon
my $mqtt;

# -------------------------------------------------------------------------------------------------
# do its work, examining the MQTT queue
sub works {
	my ( $topic, $message ) = @_;
	print "topic='$topic' message='$message'".EOL;
	Mods::Toops::msgLog( "received topic='$topic' message='$message'" );
	foreach my $it ( @{$daemon->{config}{monitoredTopics}} ){
		my $match = $topic =~ /$it->{topic}/;
		print "'$it->{topic}' ".( $match ? "match" : "doesn't match" ).EOL;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

my $hostConfig = Mods::Toops::getHostConfig();

Mods::Toops::msgErr( "no registered broker" ) if !$hostConfig->{MQTT}{broker};
Mods::Toops::msgErr( "no registered username" ) if !$hostConfig->{MQTT}{username};
Mods::Toops::msgErr( "no registered password" ) if !$hostConfig->{MQTT}{passwd};

if( !Mods::Toops::errs()){
	$mqtt = Net::MQTT::Simple->new( $hostConfig->{MQTT}{broker} );
	Mods::Toops::msgErr( "unable to connect to '$hostConfig->{MQTT}{broker}'" ) if !$mqtt;
}
if( !Mods::Toops::errs()){
	my $user = $mqtt->login( $hostConfig->{MQTT}{username}, $hostConfig->{MQTT}{passwd} );
	Mods::Toops::msgLog( "login(): $user" );
	$mqtt->subscribe( "#" => \&works );
}

my $lastScanTime;

while( !$daemon->{terminating} ){
	my $res = Mods::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	#if( $now - $lastScanTime >= $scanInterval ){
	#	works();
	#}
	$lastScanTime = $now;
	$mqtt->tick( $daemon->{listenInterval} ) if $mqtt;
}

$mqtt->disconnect();
Mods::Toops::msgLog( "terminating" );
Mods::Toops::ttpExit();
