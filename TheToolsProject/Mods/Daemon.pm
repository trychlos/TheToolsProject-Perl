# Copyright (@) 2023-2024 PWI Consulting
#
# Daemons management
#
# A daemon is identified by:
# - its JSON configuration (we are sure there is one)
# - maybe the service name it is registered with (but this registration is optional)
# As a runtime option, we can also use a concatenation of the hostname and the json basename.
#
# JSON configuration:
#
# - workDir: the daemon working directory, defaulting to site.rootDir
# - execPath: the full path to the program to be executed as the main code of the daemon
#
# Also the daemon writer mmust be conscious of the dynamic character of TheToolsProject.
# In particular and at least, many output directories (logs, temp files and so on) are built on a daily basis.
# So your configuration files must e periodically re-evaluated.
# This 'Daemon' package takes care of reevaluating both the host and the daemon configurations
# on each listenInterval.
#
# A note about technical solutions to have daemons on Win32 platforms:
# - Proc::Daemon 0.23 (as of 2024- 2- 3) is not an option.
#   According to the documentation: "INFO: Since fork is not performed the same way on Windows systems as on Linux, this module does not work with Windows. Patches appreciated!"
# - Win32::Daemon 20200728 (as of 2024- 2- 3) defines a service, and is too specialized toward win32 plaforms.
# - Proc::Background seems OK.

package Mods::Daemon;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use IO::Socket::INET;
use Sys::Hostname qw( hostname );
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::MQTT;
use Mods::Toops;

use constant {
	BUFSIZE => 4096,
	MIN_LISTEN_INTERVAL => 1,
	DEFAULT_LISTEN_INTERVAL => 5,
	MIN_ADVERTIZE_INTERVAL => 10,
	DEFAULT_ADVERTIZE_INTERVAL => 60,
	OFFLINE => "offline"
};

# ------------------------------------------------------------------------------------------------
sub _hostname {
	return uc hostname;
}

# ------------------------------------------------------------------------------------------------
sub _lastwill {
	my ( $name ) = @_;
	return {
		topic => _topic( $name ),
		payload => OFFLINE,
		retain => true
	};
}

# ------------------------------------------------------------------------------------------------
sub _running {
	my $TTPVars = Mods::Toops::TTPVars();
	return "running since $TTPVars->{run}{daemon}{started}";
}

# ------------------------------------------------------------------------------------------------
# answering to a 'status' request with:
# - running since yyyy-mm-dd hh:mi:ss
# - json: 
# - listeningPort:
sub _status {
	my ( $daemon ) = @_;
	my $answer = _running();
	$answer .= "\njson: $daemon->{json}";
	$answer .= "\nlisteningPort: $daemon->{config}{listeningPort}";
	return $answer;
}

# ------------------------------------------------------------------------------------------------
sub _topic {
	my ( $name ) = @_;
	my $topic = _hostname();
	$topic .= "/daemon";
	$topic .= "/$name";
	$topic .= "/status";
	return $topic;
}

# ------------------------------------------------------------------------------------------------
# the daemon advertize of its status every 'advertizeInterval' seconds (defaults to 60)
sub daemonAdvertize {
	my ( $daemon ) = @_;
	my $now = localtime->epoch;
	if( !$daemon->{lastAdvertized} || $now-$daemon->{lastAdvertized} >= $daemon->{advertizeInterval} ){
		my $topic = _topic( $daemon->{name} );
		my $payload = _running();
		Mods::Message::msgLog( "$topic [$payload]" );
		if( $daemon->{mqtt} ){
			$daemon->{mqtt}->retain( $topic, $payload );
		}
		$daemon->{lastAdvertized} = $now;
	}
}

# ------------------------------------------------------------------------------------------------
# the daemon answers to the client
sub daemonAnswer {
	my ( $daemon, $req, $answer ) = @_;
	Mods::Message::msgLog( "answering '$answer'" );
	$req->{socket}->send( "$answer\n" );
	$req->{socket}->shutdown( true );
}

# ------------------------------------------------------------------------------------------------
# the daemon deals with the received command
# - we are able to answer here to 'help', 'status' and 'terminate' commands and the daemon doesn't need to declare them.
sub daemonCommand {
	my ( $daemon, $req, $commands ) = @_;
	my $answer = undef;
	if( $req->{command} eq "help" ){
		$commands->{help} = 1;
		$commands->{status} = 1;
		$commands->{terminate} = 1;
		$answer = join( ', ', sort keys %{$commands} )."\nOK";
	} elsif( $req->{command} eq "status" ){
		#$answer = _running()."\nOK";
		$answer = _status( $daemon )."\nOK";
	} elsif( $req->{command} eq "terminate" ){
		$daemon->{terminating} = true;
		$answer = "OK";
	} elsif( exists( $commands->{$req->{command}} )){
		$answer = $commands->{$req->{command}}( $req );
	} else {
		$answer = "unknowned command '$req->{command}'";
	}
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# initialize The Tools Project to be usable by a running daemon
# we create a daemon.name branch in TTPVars so that all msgXxx functions will work and go to standard log
# (E):
# - the program path ($0)
# - the command line arguments (\@ARGV)
# - an optional options hash with following keys:
#   > add: a complement to the log prefix (e.g. a service name)
# returns the daemon object with:
# - json: the json configuration file path
# - config: its json evaluated configuration (and reevaluated at each listenInterval)
# - socket: the created listening socket
# - sleep: the sleep interval
# - listenInterval: computed runtime value
sub daemonInitToops {
	my ( $program, $args, $opts ) = @_;
	my $daemon = undef;
	$opts //= {};

	# init TTP
	Mods::Toops::init();
	# initialize TTPVars data to have a pretty log
	my ( $volume, $directories, $file ) = File::Spec->splitpath( $program );
	my $TTPVars = Mods::Toops::TTPVars();
	$TTPVars->{run}{daemon}{name} = $file;
	$TTPVars->{run}{daemon}{add} = $opts->{add} if $opts->{add};
	$TTPVars->{run}{daemon}{started} = localtime->strftime( '%Y-%m-%d %H:%M:%S' );

	# get and check the daemon configuration
	my $json = @{$args}[0];
	my ( $jvol, $jdirs, $jfile ) = File::Spec->splitpath( $json );
	$jfile =~ s/\.[^.]+$//;
	my $raw = getRawConfigByPath( $json );
	my $config = $raw ? getEvaluatedConfig( $raw ) : undef;
	# listening port
	if( !$config->{listeningPort} ){
		Mods::Message::msgErr( "daemon configuration must define a 'listeningPort' value, not found" );
	}
	# listen interval
	my $listenInterval = DEFAULT_LISTEN_INTERVAL;
	if( $config && exists( $config->{listenInterval} )){
		if( $config->{listenInterval} < MIN_LISTEN_INTERVAL ){
			Mods::Message::msgVerbose( "defined listenInterval=$config->{listenInterval} less than minimum accepted ".MIN_LISTEN_INTERVAL.", ignored" );
		} else {
			$listenInterval = $config->{listenInterval};
		}
	}
	# advertize interval
	my $advertizeInterval = DEFAULT_ADVERTIZE_INTERVAL;
	if( exists( $config->{advertizeInterval} )){
		if( $config->{advertizeInterval} < MIN_ADVERTIZE_INTERVAL ){
			Mods::Message::msgVerbose( "defined advertizedInterval=$config->{advertizeInterval} less than minimum accepted ".MIN_ADVERTIZE_INTERVAL.", ignored" );
		} else {
			$advertizeInterval = $config->{advertizeInterval};
		}
	}
	if( !Mods::Toops::errs()){
		Mods::Message::msgVerbose( "listeningPort='$config->{listeningPort}' listenInterval='$listenInterval' advertizeInterval='$advertizeInterval'" );
	}

	# create a listening socket
	my $socket = undef;
	if( !Mods::Toops::errs()){
		$socket = new IO::Socket::INET(
			LocalHost => '0.0.0.0',
			LocalPort => $config->{listeningPort},
			Proto => 'tcp',
			Listen => 5,
			ReuseAddr => true,
			Blocking => false,
			Timeout => 0
		) or Mods::Message::msgErr( "unable to create a listening socket: $!" );
	}

	# connect to MQTT communication bus if the host is configured for
	my $mqtt = undef;
	if( !Mods::Toops::errs()){
		my $hostConfig = Mods::Toops::getHostConfig();
		if( $hostConfig->{MQTT}{broker} && $hostConfig->{MQTT}{username} && $hostConfig->{MQTT}{passwd} ){
			$mqtt = Mods::MQTT::connect({
				broker => $hostConfig->{MQTT}{broker},
				username => $hostConfig->{MQTT}{username},
				password => $hostConfig->{MQTT}{passwd},
				will => _lastwill( $jfile )
			});
		}
	}
	if( !Mods::Toops::errs()){
		$SIG{INT} = sub { $socket->close(); Mods::Toops::ttpExit(); };
		$daemon = {
			json => $json,
			raw => $raw,
			name => $jfile,
			config => $config,
			socket => $socket,
			mqtt => $mqtt,
			listenInterval => $listenInterval,
			advertizeInterval => $advertizeInterval
		};
	}
	return $daemon;
}

# ------------------------------------------------------------------------------------------------
# periodically listen on the TCP port - reevaluate the host configuration at that moment
# this is needed to cover running when day changes and be sure that we are logging into the right file
# returns undef or a hash with:
# - client socket
# - peer host, address and port
# - command
# - args
sub daemonListen {
	my ( $daemon, $commands ) = @_;
	$commands //= {};
	# before anything else, reevalute our configurations
	# -> the daemon config
	$daemon->{config} = getEvaluatedConfig( $daemon->{raw} );
	# -> toops+site and host configurations
	Mods::Toops::ttpEvaluate();
	my $client = $daemon->{socket}->accept();
	my $result = undef;
	my $data = "";
	if( $client ){
		$result = {
			socket => $client,
			peerhost => $client->peerhost(),
			peeraddr => $client->peeraddr(),
			peerport => $client->peerport()
		};
		$client->recv( $data, BUFSIZE );
	}
	if( $result ){
		Mods::Message::msgLog( "received '$data' from '$result->{peerhost}':'$result->{peeraddr}':'$result->{peerport}'" );
		my @words = split( /\s+/, $data );
		$result->{command} = shift( @words );
		$result->{args} = \@words;
		my $answer = daemonCommand( $daemon, $result, $commands );
		daemonAnswer( $daemon, $result, $answer );
	}
	# advertize my status on communication bus
	daemonAdvertize( $daemon );
	return $result;
}

# ------------------------------------------------------------------------------------------------
# read and evaluate the daemon configuration
# (I):
# - the daemon configuration file path
# (O):
# - the evaluated result hash
sub getConfigByPath {
	my ( $json ) = @_;
	my $result = getRawConfigByPath( $json );
	$result = Mods::Toops::evaluate( $result ) if $result;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# evaluate the raw daemon configuration
# (I):
# - the raw config
# (O):
# - the evaluated result hash
sub getEvaluatedConfig {
	my ( $config ) = @_;
	my $evaluated = $config;
	$evaluated = Mods::Toops::evaluate( $evaluated );
	return $evaluated;
}

# ------------------------------------------------------------------------------------------------
# read and returns the raw daemon configuration
# (I):
# - the daemon configuration file path
# (O):
# - the raw result hash
sub getRawConfigByPath {
	my ( $json ) = @_;
	Mods::Message::msgVerbose( "Daemon::getRawConfigByPath() json='$json'" );
	my $result = Mods::Toops::jsonRead( $json );
	my $ref = ref( $result );
	if( $ref ne 'HASH' ){
		Mods::Message::msgErr( "Daemon::getRawConfigByPath() expected a hash, found a ".( $ref || 'scalar' ));
		$result = undef;
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# return the smallest interval which will be the sleep time of the daemon loop
sub getSleepTime {
	my ( @candidates ) = @_;
	my $min = -1;
	foreach my $it ( @candidates ){
		if( $it < $min || $min == -1 ){
			$min = $it;
		}
	}
	return $min;
}

# ------------------------------------------------------------------------------------------------
# terminate the daemon, gracefully closing all opened connections
sub terminate {
	my ( $daemon ) = @_;

	# close MQTT connection
	Mods::MQTT::disconnect( $daemon->{mqtt} ) if $daemon->{mqtt};
	# close TCP connection
	$daemon->{socket}->close();
	# have a log line
	Mods::Message::msgLog( "terminating" );
	# and quit the program
	Mods::Toops::ttpExit();
}

1;
