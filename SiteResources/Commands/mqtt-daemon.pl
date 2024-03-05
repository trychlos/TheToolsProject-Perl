#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the published MQTT topics
#
# Command-line arguments:
# - the full path to the JSON configuration file
# - optional "stdout" to print received message to stdout
#
# Makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;

use Data::Dumper;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::MQTT;
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
my $kept = {};
my $sysReceived = false;

# -------------------------------------------------------------------------------------------------
# some kept data are anwered to some configured commands
# the input request is:
# - client socket
# - peer host, address and port
# - command
# - args
sub doCommand {
	my ( $req ) = @_;
	Mods::Message::msgLog( "command='$req->{command}' sysReceived=$sysReceived" );
	my @answer = ();
	my $count = 0;
	foreach my $it ( keys %{$kept->{$req->{command}}} ){
		$count += 1;
		push( @answer, "$it $kept->{$req->{command}}{$it}" );
	}
	return $count ? join( "\n", @answer ) : '';
}

# -------------------------------------------------------------------------------------------------
# the received topic match a daemon configuration item
sub doMatched {
	my ( $topic, $payload, $config ) = @_;
	# is a $SYS message ?
	$sysReceived = true if $topic =~ /^\$SYS/;
	# if asked to prit to stdout, do that here (unless $SYS)
	print localtime->strftime( "%Y-%m-%d %H:%M:%S:" )." $topic $payload".EOL if haveStdout() && $topic !~ /^\$SYS/;
	# do we log the topic and/or the message ?
	my $logTopic = true;
	$logTopic = $config->{logTopic} if exists $config->{logTopic};
	my $logMessage = true;
	$logMessage = $config->{logMessage} if exists $config->{logMessage};
	if( $logTopic || $logMessage ){
		my $logged = '';
		$logged .= "logTopic=$logTopic";
		$logged .= " topic='$topic'" if $logTopic;
		$logged .= " logMessage=$logMessage";
		$logged .= " payload='$payload'" if $logMessage;
		Mods::Message::msgLog( "$logged" );
	}
	# do we want keep and answer with the received data ?
	my $command = undef;
	$command = $config->{command} if exists $config->{command};
	if( $command ){
		$kept->{$command}{$topic} = $payload;
	}
}

# -------------------------------------------------------------------------------------------------
# whether to print received messages to stdout
sub haveStdout {
	return scalar @ARGV > 1 && $ARGV[1] eq "stdout";
}

# -------------------------------------------------------------------------------------------------
# setup the commands hash before the first listening loop
sub setCommands {
	foreach my $key ( keys %{$daemon->{config}{topics}} ){
		if( exists( $daemon->{config}{topics}{$key}{command} )){
			$commands->{$daemon->{config}{topics}{$key}{command}} = \&doCommand;
		}
	}
}

# -------------------------------------------------------------------------------------------------
# do its work, examining the MQTT queue
sub works {
	my ( $topic, $payload ) = @_;
	#print "$topic".EOL;
	foreach my $key ( keys %{$daemon->{config}{topics}} ){
		my $match = $topic =~ /$key/;
		#print "topic='$topic' key='$key' match=$match".EOL;
		if( $match ){
			doMatched( $topic, $payload, $daemon->{config}{topics}{$key} );
		}
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !Mods::Toops::errs()){
	$mqtt = Mods::MQTT::connect();
}
if( !Mods::Toops::errs()){
	$mqtt->subscribe( '#' => \&works, '$SYS/#' => \&works );
	setCommands();
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

Mods::MQTT::disconnect( $mqtt );
Mods::Daemon::terminate( $daemon );
