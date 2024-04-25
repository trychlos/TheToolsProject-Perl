#!perl
#!/usr/bin/perl
# @(#) Connect to and monitor the published MQTT topics.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --[no]stdout            whether to print the found non-SYS topics on stdout [${stdout}]
# @(-) --[no]sys               whether to print the found SYS topics on stdout [${sys}]
#
# @(@) This script is expected to be run as a daemon, started via a 'daemon.pl start -json <filename.json>' command.
#
# This script is mostly written like a TTP verb but is not. This is an example of how to take advantage of TTP
# to write your own (rather pretty and efficient) daemon.
# Just to be sure: this makes use of Toops, but is not part itself of Toops (though a not so bad example of application).
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Getopt::Long;
use Time::Piece;

use TTP;
use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );
use TTP::MQTT;
use TTP::Path;
use vars::global qw( $ttp );

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	stdout => 'no',
	sys => 'no'
};

my $opt_json = $defaults->{json};
my $opt_stdout = undef;
my $opt_sys = undef;

my $commands = {
	#help => \&help,
};

my $TTPVars = TTP::Daemon::init();
my $daemon = undef;

# specific to this daemon
my $mqtt;
my $kept = {};
my $logFile = File::Spec->catdir( TTP::Path::logsDailyDir(), 'mqtt-daemon.log' );

# -------------------------------------------------------------------------------------------------
# some kept data are anwered to some configured commands
# the input request is:
# - client socket
# - peer host, address and port
# - command
# - args
sub doCommand {
	my ( $req ) = @_;
	msgLog( "command='$req->{command}'" );
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
	my $isSYS = ( $topic =~ /^\$SYS/ );
	# whether to log the message
	my $toLog = false;
	$toLog = $config->{toLog} if exists $config->{toLog};
	msgLog( "$topic [$payload]", { logFile => $logFile }) if $toLog;
	# whether to print to stdout
	my $toStdout = false;
	$toStdout = $config->{toStdout} if exists $config->{toStdout};
	$toStdout = $opt_stdout if defined $opt_stdout && !$isSYS;
	$toStdout = $opt_sys if defined $opt_sys && $isSYS;
	print localtime->strftime( "%Y-%m-%d %H:%M:%S:" )." $topic $payload".EOL if $toStdout;
	# do we want keep and answer with the received data ?
	my $command = undef;
	$command = $config->{command} if exists $config->{command};
	if( $command ){
		$kept->{$command}{$topic} = $payload;
	}
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"json=s"			=> \$opt_json,
	"stdout!"			=> \$opt_stdout,
	"sys!"				=> \$opt_sys )){

		msgOut( "try '$ttp->{run}{command}{basename} --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$daemon->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found stdout='".( defined $opt_stdout ? ( $opt_stdout ? 'true':'false' ) : '(undef)' )."'" );
msgVerbose( "found sys='".( defined $opt_sys ? ( $opt_sys ? 'true':'false' ) : '(undef)' )."'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	$daemon = TTP::Daemon::run( $opt_json );
}
if( !TTP::errs()){
	$mqtt = TTP::MQTT::connect();
}
if( !TTP::errs()){
	$mqtt->subscribe( '#' => \&works, '$SYS/#' => \&works );
	setCommands();
}
if( TTP::errs()){
	TTP::exit();
}

my $lastScanTime;

while( !$daemon->{terminating} ){
	my $res = TTP::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	$lastScanTime = $now;
	$mqtt->tick( $daemon->{listenInterval} ) if $mqtt;
}

TTP::MQTT::disconnect( $mqtt );
TTP::Daemon::terminate( $daemon );
