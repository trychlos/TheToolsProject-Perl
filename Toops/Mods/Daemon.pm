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
use Mods::Toops;

use constant {
	BUFSIZE => 4096,
	ADVERTIZE_INTERVAL => 60,
	MIN_INTERVAL => 1
};

# ------------------------------------------------------------------------------------------------
sub _hostname {
	return uc hostname;
}

# ------------------------------------------------------------------------------------------------
sub _running {
	my $TTPVars = Mods::Toops::TTPVars();
	return "running since $TTPVars->{run}{daemon}{started}";
}

# ------------------------------------------------------------------------------------------------
# the daemon advertize of its status every minute
sub daemonAdvertize {
	my ( $daemon ) = @_;
	my $now = localtime->epoch;
	my $advertizeInterval = ADVERTIZE_INTERVAL;
	$advertizeInterval = $daemon->{config}{advertizeInterval} if exists $daemon->{config}{advertizeInterval} && $daemon->{config}{advertizeInterval} >= MIN_INTERVAL;
	if( !$daemon->{lastAdvertize} || $now-$daemon->{lastAdvertize} >= $advertizeInterval ){
		my $topic = _hostname();
		$topic .= "/daemon";
		$topic .= "/$daemon->{json}";
		$topic .= "/status";
		my $message = _running();
		Mods::Toops::msgLog( `mqtt.pl publish -topic $topic -message $message -retain` );
		$daemon->{lastAdvertize} = $now;
	}
}

# ------------------------------------------------------------------------------------------------
# the daemon answers to the client
sub daemonAnswer {
	my ( $daemon, $req, $answer ) = @_;
	Mods::Toops::msgLog( "answering '$answer'" );
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
		$answer = _running()."\nOK";
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
# returns the daemon object with:
# - json: the json configuration file path
# - config: its json evaluated configuration
# - socket: the created listening socket
# - sleep: the sleep interval
sub daemonInitToops {
	my ( $program, $args ) = @_;
	my $daemon = undef;

	# init TTP
	Mods::Toops::initSiteConfiguration();
	Mods::Toops::initLogs();
	Mods::Toops::msgLog( "executing $program ".join( ' ', @ARGV ));
	Mods::Toops::initHostConfiguration();

	# initialize TTPVars data to have a pretty log
	my ( $volume, $directories, $file ) = File::Spec->splitpath( $program );
	my $TTPVars = Mods::Toops::TTPVars();
	$TTPVars->{run}{daemon}{name} = $file;
	$TTPVars->{run}{daemon}{started} = localtime->strftime( '%Y-%m-%d %H:%M:%S' );

	# get and check the daemon configuration
	my $json = @{$args}[0];
	my $config = getConfigByPath( $json );
	Mods::Toops::msgErr( "JSON configuration must define a daemon 'listeningPort' value, not found" ) if !$config->{listeningPort};
	my $listenInterval = MIN_INTERVAL;
	if( !Mods::Toops::errs()){
		if( $config->{listenInterval} ){
			if( $config->{listenInterval} < $listenInterval ){
				Mods::Toops::msgVerbose( "defined listenInterval=$config->{listenInterval} less than minimum accepted '$listenInterval', ignored" );
			} else {
				$listenInterval = $config->{listenInterval};
			}
		}
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
		) or Mods::Toops::msgErr( "unable to create a listening socket: $!" );
	}
	if( !Mods::Toops::errs()){
		$SIG{INT} = sub { $socket->close(); Mods::Toops::ttpExit(); };
		$daemon = {
			json => $json,
			config => $config,
			socket => $socket,
			listenInterval => $listenInterval
		};
	}
	return $daemon;
}

# ------------------------------------------------------------------------------------------------
# periodically listen on the TCP port
# returns undef or a hash with:
# - client socket
# - peer host, address and port
# - command
# - args
sub daemonListen {
	my ( $daemon, $commands ) = @_;
	$commands //= {};
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
		Mods::Toops::msgLog( "received '$data' from '$result->{peerhost}':'$result->{peeraddr}':'$result->{peerport}'" );
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
# read the daemon configuration
sub getConfigByPath {
	my ( $json ) = @_;
	#Mods::Toops::msgVerbose( "Daemon::getConfigByPath() json='$json'" );
	my $res = Mods::Toops::evaluate( Mods::Toops::jsonRead( $json ));
	return undef if ref( $res ) ne 'HASH' || !scalar keys %{$res};
	return $res;
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

1;
