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
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Toops;

use constant {
	BUFSIZE => 4096
};

# ------------------------------------------------------------------------------------------------
# the daemon answers to the client
sub daemonAnswer {
	my ( $req, $answer ) = @_;
	Mods::Toops::msgLog( "answering '$answer'" );
	$req->{socket}->send( "$answer\n" );
	$req->{socket}->shutdown( true );
}

# ------------------------------------------------------------------------------------------------
# the daemon deals with the received command
# - we are able to answer here to 'help', 'status' and 'terminate' commands and the daemon doesn't need to declare them.
sub daemonCommand {
	my ( $req, $commands ) = @_;
	my $answer = undef;
	my $TTPVars = Mods::Toops::TTPVars();
	if( $req->{command} eq "help" ){
		$commands->{help} = 1;
		$commands->{status} = 1;
		$commands->{terminate} = 1;
		$answer = join( ', ', sort keys %{$commands} )."\nOK";
	} elsif( $req->{command} eq "status" ){
		$answer = "running since $TTPVars->{run}{daemon}{started}\nOK";
	} elsif( $req->{command} eq "terminate" ){
		$TTPVars->{run}{daemon}{terminating} = true;
		$answer = "OK";
	} elsif( exists( $commands->{$req->{command}} )){
		$answer = $commands->{$req->{command}}( $req );
	} else {
		$answer = "unknowned command '$req->{command}'";
	}
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# periodically listen on the TCP port
sub daemonListen {
	my ( $socket, $commands ) = @_;
	my $client = $socket->accept();
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
		if( $commands ){
			my $answer = daemonCommand( $result, $commands );
			daemonAnswer( $result, $answer );
		}
	}
	return $result;
}

# ------------------------------------------------------------------------------------------------
# create a listening socket
sub daemonCreateListeningSocket {
	my ( $config ) = @_;
	my $socket = new IO::Socket::INET(
		LocalHost => '0.0.0.0',
		LocalPort => $config->{listeningPort},
		Proto => 'tcp',
		Listen => 5,
		ReuseAddr => true,
		Blocking => false,
		Timeout => 0
	) or Mods::Toops::msgErr( "unable to create a listening socket: $!" );

	if( $socket ){
		$SIG{INT} = sub { $socket->close(); Mods::Toops::ttpExit(); };
	}
	return $socket;
}

# ------------------------------------------------------------------------------------------------
# initialize The Tools Project to be usable by a running daemon
# we create a daemon.name branch in TTPVars so that all msgXxx functions will work and go to standard log
sub daemonInitToops {
	my ( $program ) = @_;
	Mods::Toops::initSiteConfiguration();
	Mods::Toops::initLogs();
	my ( $volume, $directories, $file ) = File::Spec->splitpath( $program );
	# keep the sufix when advertizing about the daemon
	#$file =~ s/\.[^.]+$//;
	my $TTPVars = Mods::Toops::TTPVars();
	$TTPVars->{run}{daemon}{name} = $file;
	$TTPVars->{run}{daemon}{started} = localtime->strftime( '%Y-%m-%d %H:%M:%S' );
	$TTPVars->{run}{daemon}{terminating} = false;
	Mods::Toops::msgLog( "executing $program ".join( ' ', @ARGV ));
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

1;
