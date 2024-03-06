#!perl
#!/usr/bin/perl
# @(#) Connect to and monitor the published MQTT topics.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]stdout            whether to print the found topics on stdout [${stdout}]
#
# @(@) This script is expected to be run as a daemon, started via a 'daemon.pl start -json <filename.json>' command.
#
# This script is mostly written like a TTP verb but is not. This is an example of how to take advantage of TTP
# to write your own (rather pretty and efficient) daemon.
# Just to be sure: this makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Message;
use Mods::MQTT;
use Mods::Path;
use Mods::Toops;

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	stdout => 'no'
};

my $opt_json = $defaults->{json};
my $opt_stdout = undef;

my $commands = {
	#help => \&help,
};

my $TTPVars = Mods::Daemon::init();
my $daemon = undef;

# specific to this daemon
my $mqtt;
my $kept = {};
my $logFile = File::Spec->catdir( Mods::Path::logsDailyDir(), 'mqtt-daemon.log' );

# -------------------------------------------------------------------------------------------------
# some kept data are anwered to some configured commands
# the input request is:
# - client socket
# - peer host, address and port
# - command
# - args
sub doCommand {
	my ( $req ) = @_;
	Mods::Message::msgLog( "command='$req->{command}'" );
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
# known actions which can be executed on each message:
# - toLog: log the topic and its payload to a mqtt.log besides of TTP/main.log, defaulting to false
# - toStdout: display the topic and its payload on stdout, defaulting to false
sub doMatched {
	my ( $topic, $payload, $config ) = @_;
	# is a $SYS message ?
	my $sysReceived = ( $topic =~ /^\$SYS/ );
	# whether to log the message
	my $toLog = false;
	$toLog = $config->{toLog} if exists $config->{toLog};
	Mods::Message::msgLog( "$topic [$payload]", { logFile => $logFile }) if $toLog;
	# whether to print to stdout
	my $toStdout = false;
	$toStdout = $config->{toStdout} if exists $config->{toStdout};
	$toStdout = $opt_stdout if defined $opt_stdout;
	print localtime->strftime( "%Y-%m-%d %H:%M:%S:" )." $topic $payload".EOL if $toStdout;
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

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"json=s"			=> \$opt_json,
	"stdout!"			=> \$opt_stdout )){

		Mods::Message::msgOut( "try '$TTPVars->{run}{command}{basename} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpExtern( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Message::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found json='$opt_json'" );
Mods::Message::msgVerbose( "found stdout='".( defined $opt_stdout ? ( $opt_stdout ? 'true':'false' ) : '(undef)' )."'" );

Mods::Message::msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !Mods::Toops::errs()){
	$daemon = Mods::Daemon::run( $opt_json );
}
if( !Mods::Toops::errs()){
	$mqtt = Mods::MQTT::connect();
}
if( !Mods::Toops::errs()){
	$mqtt->subscribe( '#' => \&works, '$SYS/#' => \&works );
	setCommands();
}
if( Mods::Toops::errs()){
	Mods::Toops::ttpExit();
}

my $lastScanTime;

while( !$daemon->{terminating} ){
	my $res = Mods::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	$lastScanTime = $now;
	$mqtt->tick( $daemon->{listenInterval} ) if $mqtt;
}

Mods::MQTT::disconnect( $mqtt );
Mods::Daemon::terminate( $daemon );
