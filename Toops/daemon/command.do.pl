# @(#) send a command to a running daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --command=<command>     the command to be sent to the daemon [${command}]
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
	json => '',
	command => ''
};

my $opt_json = $defaults->{json};
my $opt_command = $defaults->{command};

my $daemonConfig = undef;

# -------------------------------------------------------------------------------------------------
# send a command to the daemon
sub doSend {
	my $socket = new IO::Socket::INET(
		PeerHost => 'localhost',
		PeerPort => $daemonConfig->{listeningPort},
		Proto => 'tcp'
	) or Mods::Toops::msgErr( "unable to connect: $!" ) if !$socket;
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
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"json=s"			=> \$opt_json,
	"command=s"			=> \$opt_command )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found json='$opt_json'" );
Mods::Toops::msgVerbose( "found command='$opt_command'" );

# the json is mandatory
$daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
# and a command too
Mods::Toops::msgErr( "'--command' option is mandatory, but is not specified" ) if !$opt_command;

if( !Mods::Toops::errs()){
	doSend();
}

Mods::Toops::ttpExit();
