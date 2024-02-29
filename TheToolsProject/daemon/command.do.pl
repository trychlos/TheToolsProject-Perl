# @(#) send a command to a running daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --command=<command>     the command to be sent to the daemon [${command}]
# @(-) --ignore                ignore the return code if the daemon is not active [${ignore}]
#
# @(@) A command is a simple string. The daemon is expected to (at least) acknowledge it.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use IO::Socket::INET;

# auto-flush on socket
$| = 1;

use Mods::Constants;
use Mods::Daemon;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	port => '',
	command => '',
	ignore => 'no'
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_command = $defaults->{command};
my $opt_ignore = false;

my $daemonConfig = undef;

# -------------------------------------------------------------------------------------------------
# send a command to the daemon
sub doSend {
	# connect
	my $port = $opt_port;
	$port = $daemonConfig->{listeningPort} if $daemonConfig;
	# triggers an error if the daemon is not active
	my $socket = new IO::Socket::INET(
		PeerHost => 'localhost',
		PeerPort => $port,
		Proto => 'tcp'
	) or Mods::Toops::msgErr( "unable to connect: $!" ) if !$socket;

	# send the command
	if( $socket ){
		my $size = $socket->send( $opt_command );
		Mods::Toops::msgVerbose( "sent '$opt_command' to the server ($size bytes)" );
		# notify server that request has been sent
		$socket->shutdown( true );
		# receive a response of up to 4096 characters from server
		my $response = "";
		$socket->recv( $response, 4096 );
		print "$response";
		$socket->close();
		Mods::Toops::msgOut( "success" );

	# if the daemon was not active, and the '--ignore' flag has been set, the reset the current exist code
	# and output a corresponding message to stdout
	} elsif( $opt_ignore ){
		$TTPVars->{run}{exitCode} = 0;
		Mods::Toops::msgOut( "daemon is not active, but '--ignore' flag is set, so set rc to zero" );
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
	"port=i"			=> \$opt_port,
	"command=s"			=> \$opt_command,
	"ignore!"			=> \$opt_ignore )){

		Mods::Toops::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found json='$opt_json'" );
Mods::Toops::msgVerbose( "found port='$opt_port'" );
Mods::Toops::msgVerbose( "found command='$opt_command'" );
Mods::Toops::msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );

# either the json or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	Mods::Toops::msgErr( "one of '--json' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	Mods::Toops::msgErr( "one of '--json' or '--port' options must be specified, both were found" );
}
#if a json is specified, must have a listeningPort
if( $opt_json ){
	$daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
	# must have a listening port
	Mods::Toops::msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
}
# and a command too
Mods::Toops::msgErr( "'--command' option is mandatory, but is not specified" ) if !$opt_command;

if( !Mods::Toops::errs()){
	doSend();
}

Mods::Toops::ttpExit();
