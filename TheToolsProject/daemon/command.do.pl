# @(#) send a command to a running daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --command=<command>     the command to be sent to the daemon [${command}]
#
# @(@) A command is a simple string. The daemon is expected to (at least) acknowledge it.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use IO::Socket::INET;

# auto-flush on socket
$| = 1;

use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	port => '',
	command => ''
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_command = $defaults->{command};

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
		Proto => 'tcp',
		Type => SOCK_STREAM
	) or msgErr( "unable to connect: $!" ) if !$socket;

	# send the command
	if( $socket ){
		my $size = $socket->send( $opt_command );
		msgVerbose( "sent '$opt_command' to the server ($size bytes)" );
		# notify server that request has been sent
		$socket->shutdown( SHUT_WR );
		# receive a response of up to 4096 characters from server
		my $response = "";
		while( !isOk( $response )){
			$socket->recv( $response, 4096 );
			print "$response";
			msgLog( $response );
		}
		$socket->close();
		msgOut( "success" );
	}
}

# -------------------------------------------------------------------------------------------------
# whether the received answer is just 'OK'
sub isOk {
	my ( $answer ) = @_;
	my @lines = split( /[\r\n]+/, $answer );
	foreach my $line ( @lines ){
		return true if $line =~ m/^[0-9]+\s+OK/;
	}
	return false;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"verbose!"			=> \$ttp->{run}{verbose},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"json=s"			=> \$opt_json,
	"port=i"			=> \$opt_port,
	"command=s"			=> \$opt_command )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found port='$opt_port'" );
msgVerbose( "found command='$opt_command'" );

# either the json or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	msgErr( "one of '--json' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--port' options must be specified, both were found" );
}
#if a json is specified, must have a listeningPort
if( $opt_json ){
	$daemonConfig = TTP::Daemon::getConfigByPath( $opt_json );
	# must have a listening port
	msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
}
# and a command too
msgErr( "'--command' option is mandatory, but is not specified" ) if !$opt_command;

if( !TTP::errs()){
	doSend();
}

TTP::exit();
