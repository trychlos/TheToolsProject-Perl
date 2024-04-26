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
# - enabled: whether this configuration is enabled
# - execPath: the full path to the program to be executed as the main code of the daemon
# - listeningPort: the listening port number
# - listeningInterval: the interval in sec. between two listening loops
# - messagingInterval: either false (do not advertize to messaging system), or the advertizing interval
#
# Also the daemon writer mmust be conscious of the dynamic character of TheToolsProject.
# In particular and at least, many output directories (logs, temp files and so on) may be built on a daily basis.
# So your configuration files must be periodically re-evaluated.
# This 'Daemon' class takes care of reevaluating both the host and the daemon configurations
# on each listeningInterval.
#
# A note about technical solutions to have daemons on Win32 platforms:
# - Proc::Daemon 0.23 (as of 2024- 2- 3) is not an option.
#   According to the documentation: "INFO: Since fork is not performed the same way on Windows systems as on Linux, this module does not work with Windows. Patches appreciated!"
# - Win32::Daemon 20200728 (as of 2024- 2- 3) defines a service, and is too specialized toward win32 plaforms.
# - Proc::Background seems OK.

package TTP::Daemon;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Spec;
use IO::Socket::INET;
use Proc::Background;
use Role::Tiny::With;
use Time::Piece;
use vars::global qw( $ttp );

with 'TTP::Enableable', 'TTP::Acceptable', 'TTP::Findable', 'TTP::Helpable', 'TTP::JSONable', 'TTP::Optionable', 'TTP::Sleepable', 'TTP::Runnable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::MQTT;

use constant {
	BUFSIZE => 4096,
	MIN_LISTEN_INTERVAL => 1,
	DEFAULT_LISTEN_INTERVAL => 5,
	MIN_MESSAGING_INTERVAL => 10,
	DEFAULT_MESSAGING_INTERVAL => 60,
	OFFLINE => "offline"
};

# auto-flush on socket
$| = 1;

my $Const = {
	# the commands the class manages for all daemons
	commonCommands => {
		help => \&_do_help,
		status => \&_do_status,
		terminate => \&_do_terminate
	},
	# how to find the daemons configuration files
	finder => {
		dirs => [
			'etc/daemons',
			'daemons'
		],
		sufix => '.json'
	}
};

### Private functions
### Must be explicitely called with $self as first argument

# ------------------------------------------------------------------------------------------------
# answers to 'help' command
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - the list of the available commands

sub _do_help {
	my ( $self, $req, $commands ) = @_;
	my $hash = {};
	foreach my $k ( keys %{$commands} ){
		$hash->{$k} = 1;
	}
	foreach my $k ( keys %{$Const->{commonCommands}} ){
		$hash->{$k} = 1;
	}
	my $answer = join( ', ', sort keys %{$hash} ).EOL;
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# answers to 'status' command with three lines
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - running since yyyy-mm-dd hh:mi:ss
# - json: 
# - listeningPort:

sub _do_status {
	my ( $self, $req, $commands ) = @_;

	my $answer = $self->_running().EOL;
	$answer .= "json: ".$self->jsonPath().EOL;
	$answer .= "listeningPort: ".$self->listeningPort().EOL;

	return $answer;
}

# ------------------------------------------------------------------------------------------------
# answers to 'terminate' command
# (I):
# - the received request
# - the daemon-specific commands
# (O):
# - an empty answer

sub _do_terminate {
	my ( $self, $req, $commands ) = @_;

	$self->terminateAsk();

	my $answer = "";
	return $answer;
}

### Private methods

# ------------------------------------------------------------------------------------------------
# initialize the TTP daemon
# when entering here, the JSON config has been successfully read, evaluated and checked
# (I):
# - none
# (O):
# - returns this same object

sub _daemonize {
	my ( $self ) = @_;

	my $listeningPort = $self->listeningPort();
	my $listeningInterval = $self->listeningInterval();
	my $messagingInterval = $self->messagingInterval();
	msgVerbose( "listeningPort='$listeningPort' listeningInterval='$listeningInterval' messagingInterval='$messagingInterval'" );

	# create a listening socket
	if( !TTP::errs()){
		$self->{_socket} = new IO::Socket::INET(
			LocalHost => '0.0.0.0',
			LocalPort => $listeningPort,
			Proto => 'tcp',
			Type => SOCK_STREAM,
			Listen => 5,
			ReuseAddr => true,
			Blocking => false,
			Timeout => 0
		) or msgErr( "unable to create a listening socket: $!" );
	}

	# connect to MQTT communication bus if the host is configured for
	if( !TTP::errs() && $messagingInterval ){
		$self->{_mqtt} = TTP::MQTT::connect({
			will => $self->_lastwill()
		});
	}
	if( !TTP::errs()){
		$SIG{INT} = sub { $self->{_socket}->close(); TTP::exit(); };
	}

	return $self;
}

# ------------------------------------------------------------------------------------------------
# build and returns the last will MQTT message for the daemon

sub _lastwill {
	my ( $self ) = @_;
	return {
		topic => $self->_topic(),
		payload => OFFLINE,
		retain => true
	};
}

# ------------------------------------------------------------------------------------------------

sub _running {
	my ( $self ) = @_;

	return "running since ".$self->runnableStarted();
}

# ------------------------------------------------------------------------------------------------

sub _topic {
	my ( $self ) = @_;
	my $topic = $ttp->node()->name();
	$topic .= "/daemon";
	$topic .= "/".$self->name();
	$topic .= "/status";
	return $topic;
}

### Public methods

# ------------------------------------------------------------------------------------------------
# the daemon answers to the client
# the answer string is expected to be '\n'-terminated
# we send the answer prefixing each line by the daemon pid
# (I):
# - the received request
# - the computed answer
# (O):
# - this same object

sub doAnswer {
	my ( $self, $req, $answer ) = @_;

	msgLog( "answering '$answer' and ok-ing" );
	foreach my $line ( split( /[\r\n]+/, $answer )){
		$req->{socket}->send( "$$ $line\n" );
	}
	$req->{socket}->send( "$$ OK\n" );
	$req->{socket}->shutdown( SHUT_WR );

	return $self;
}

# ------------------------------------------------------------------------------------------------
# the daemon deals with the received command
# we are able to answer here to 'help', 'status' and 'terminate' commands and the daemon doesn't
# need to declare them.
# (I):
# - the received request
# - the hash of the daemon specific commands
# (O):
# - the computed answer as an array ref

sub doCommand {
	my ( $self, $req, $commands ) = @_;

	my $answer = undef;

	# first try to execute a specific daemon command, passing it the received request
	if( $commands->{$req->{command}} ){
		$answer = $commands->{$req->{command}}( $req );

	# else ty to execute a standard command
	} elsif( $Const->{commonCommands}{$req->{command}} ){
		$answer = $self->$Const->{commonCommands}{$req->{command}}( $req, $commands );

	# else the command is just unknowned
	} else {
		$answer = "unknowned command '$req->{command}'\n";
	}
	return $answer;
}

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the daemon command basename
# (I]:
# - none
# (O):
# - the command e.g. 'alert-daemon.pl'

sub command {
	my ( $self ) = @_;

	return $self->runnableBNameFull();
}

# ------------------------------------------------------------------------------------------------
# returns common commands
# (useful when the daeon wants override a standard answer)

sub commonCommands {
	return $Const->{commonCommands};
}

# ------------------------------------------------------------------------------------------------
# Returns the execPath of the daemon
# This is a mandatory configuration item.
# (I):
# - none
# (O):
# - returns the execPath

sub execPath {
	my ( $self ) = @_;

	return $self->jsonData()->{execPath};
}

# ------------------------------------------------------------------------------------------------
# periodically listen on the TCP port - reevaluate the host configuration at that moment
# this is needed to cover running when day changes and be sure that we are logging into the right file
# (I):
# - the hash of commands defined by the daemon
# - an optional ref to the hash which holds the daemon configuration
#   it is re-evaluated if provided
# (O):
# returns undef or a hash with:
# - client socket
# - peer host, address and port
# - received command
# - args

sub listen {
	my ( $self, $commands, $config ) = @_;
	$commands //= {};

	# before anything else, reevalute our configurations
	# -> the daemon config
	$self->evaluate();
	$config = $self->jsonData() if defined $config;
	# -> toops+site and execution host configurations
	$self->ttp()->evaluate();

	my $client = $self->{_socket}->accept();
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
		msgLog( "received '$data' from '$result->{peerhost}':'$result->{peeraddr}':'$result->{peerport}'" );
		my @words = split( /\s+/, $data );
		$result->{command} = shift( @words );
		$result->{args} = \@words;
		my $answer = $self->doCommand( $result, $commands );
		$self->doAnswer( $result, $answer );
	}

	# advertize the daemon status to the messaging system if asked for
	$self->advertize();

	return $result;
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two listening loops
# We provide a default value if not specified in the configuration file.
# (I):
# - none
# (O):
# - returns the listening interval

sub listeningInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{listeningInterval};
	$interval = DEFAULT_LISTEN_INTERVAL if !defined $interval;
	if( $interval < MIN_LISTEN_INTERVAL ){
		msgVerbose( "defined listeningInterval=$interval less than minimum accepted ".MIN_LISTEN_INTERVAL.", ignored" );
		$interval = DEFAULT_LISTEN_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Returns the listening port of the daemon
# This is a mandatory configuration item.
# (I):
# - none
# (O):
# - returns the listening port

sub listeningPort {
	my ( $self ) = @_;

	return $self->jsonData()->{listeningPort};
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon configuration has been successfully loaded
# (I):
# - none
# (O):
# - returns true|false

sub loaded {
	my ( $self ) = @_;

	return $self->jsonLoaded();
}

# ------------------------------------------------------------------------------------------------
# Returns the interval in sec. between two advertizings to messaging system.
# May be set to false in the configuration file to disable that.
# (I):
# - none
# (O):
# - returns the listening interval, which may be zero if disabled

sub messagingInterval {
	my ( $self ) = @_;

	my $interval = $self->jsonData()->{messagingInterval};
	$interval = DEFAULT_MESSAGING_INTERVAL if !defined $interval;
	if( $interval && $interval < MIN_MESSAGING_INTERVAL ){
		msgVerbose( "defined messagingInterval=$interval less than minimum accepted ".MIN_MESSAGING_INTERVAL.", ignored" );
		$interval = DEFAULT_MESSAGING_INTERVAL;
	}

	return $interval;
}

# ------------------------------------------------------------------------------------------------
# Returns the canonical name of the daemon which happens to be the basename of its configuration file
# without the extension
# (I):
# - none
# (O):
# - returns the name of the daemon, or undef if the initialization has not been successful

sub name {
	my ( $self ) = @_;

	return undef if !$self->loaded();

	return $self->runnableQualifier();
}

# -------------------------------------------------------------------------------------------------
# Set the configuration path
# (I):
# - a hash argument with following keys:
#   > json: the path to the JSON configuration file
# (O):
# - true|false whether the configuration has been successfully loaded

sub setConfig {
	my ( $self, $args ) = @_;
	$args //= {};

	#only manage JSON configuration at the moment
	if( $args->{json} ){
		my $loaded = false;
		my $acceptable = {
			accept => sub { return $self->enabled( @_ ); },
			opts => {
				type => 'JSON'
			}
		};
		# JSOnable role takes care of validating the acceptability and the enable-ity
		$loaded = $self->jsonLoad({ path => $args->{json}, acceptable => $acceptable });
		# evaluate the data if success
		if( $loaded ){
			# set a runnable qualifier as soon as we can
			my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $self->jsonPath());
			$bname =~ s/\.[^\.]*$//;
			$self->runnableSetQualifier( $bname );

			# we can now may evaluate...
			$self->evaluate();

			# must have a listening port
			msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$self->listeningPort();

			my $program = $self->execPath();
			msgErr( "daemon configuration must define an 'execPath' value, not found" ) if !$program;
			msgErr( "execPath='$program' not found or not readable" ) if ! -r $program;

			# if the JSON configuration misses some informations, then says we cannot load
			if( TTP::errs()){
				$self->jsonLoaded( false );
			} else {
				$self->_daemonize();
			}
		}
	}

	return $self->loaded();
}

# ------------------------------------------------------------------------------------------------
# Parent process
# Start the daemon
# (I):
# - none
# (O):
# - returns true|false

sub start {
	my ( $self ) = @_;

	my $program = $self->execPath();
	my $proc = Proc::Background->new( "perl $program -json ".$self->jsonPath()." ".join( ' ', @ARGV ));

	return $proc;
}

# ------------------------------------------------------------------------------------------------
# terminate the daemon, gracefully closing all opened connections

sub terminate {
	my ( $self ) = @_;

	# close MQTT connection
	TTP::MQTT::disconnect( $self->{_mqtt} ) if $self->{_mqtt};

	# close TCP connection
	$self->{_socket}->close();

	# have a log line
	msgLog( "terminating" );

	# and quit the program
	TTP::exit();
}

# ------------------------------------------------------------------------------------------------
# Ask for daemon termination by setting the termination flag
# (I):
# - none
# (O):
# - none

sub terminateAsk {
	my ( $self ) = @_;

	$self->{_terminating} = true;
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon has been asked to terminate
# (I):
# - none
# (O):
# - returns true|false

sub terminating {
	my ( $self ) = @_;

	return $self->{_terminating};
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of subdirectories of TTP_ROOTS in which we may find daemons configuration files
# (I):
# - none
# (O):
# - returns the list of subdirectories which may contain the JSON daemons configuration files as
#   an array ref

sub dirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = $ttp->var( 'daemonsDirs' ) || $class->finder()->{dirs};

	return $dirs;
}

# ------------------------------------------------------------------------------------------------
# Returns the (hardcoded) specifications to find the daemons configuration files
# (I):
# - none
# (O):
# - returns the list of directories which may contain the JSON daemons configuration files as
#   an array ref

sub finder {
	return $Const->{finder};
}

# -------------------------------------------------------------------------------------------------
# Run by the daemon program
# Initialize the TTP environment as soon as possible
# Instanciating the Daemon also initialize the underlying Runnable

sub init {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	$ttp = TTP::EP->new();
	$ttp->bootstrap();

	my $daemon = $class->new( $ttp );
	$daemon->{_initialized} = true;
	$daemon->run();

	return $daemon;
}

# -------------------------------------------------------------------------------------------------
# Constructor
# We never abort if we cannot find or load the daemon configuration file. We rely instead on the
# 'jsonable-loaded' flag that the caller MUST test.
# (I]:
# - the TTP EP entry point
# - an optional argument object with following keys:
#   > path: the absolute path to the JSON configuration file
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp );
	bless $self, $class;

	$self->{_initialized} = false;
	$self->{_terminating} = false;

	# if a path is specified, then we try to load it
	# JSOnable role takes care of validating the acceptability and the enable-ity
	if( $args && $args->{path} ){
		$self->setConfig({ json => $args->{path} });
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# Destructor
# (I]:
# - instance
# (O):

sub DESTROY {
	my $self = shift;
	$self->SUPER::DESTROY();
	return;
}

### Global functions
### Note for the developer: while a global function doesn't take any argument, it can be called both
### as a class method 'TTP::Package->method()' or as a global function 'TTP::Package::method()',
### the former being preferred (hence the writing inside of the 'Class methods' block).

###
###
###

# ------------------------------------------------------------------------------------------------
# the daemon advertize of its status every 'messagingInterval' seconds (defaults to 60)
sub daemonAdvertize {
	my ( $daemon ) = @_;
	my $now = localtime->epoch;
	if( !$daemon->{lastAdvertized} || $now-$daemon->{lastAdvertized} >= $daemon->{messagingInterval} ){
		my $topic = _topic( $daemon->{name} );
		my $payload = _running();
		msgLog( "$topic [$payload]" );
		if( $daemon->{mqtt} ){
			$daemon->{mqtt}->retain( $topic, $payload );
		}
		$daemon->{lastAdvertized} = $now;
	}
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
	$evaluated = TTP::evaluate( $evaluated );
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
	msgVerbose( "Daemon::getRawConfigByPath() json='$json'" );
	my $result = TTP::jsonRead( $json );
	my $ref = ref( $result );
	if( $ref ne 'HASH' ){
		msgErr( "Daemon::getRawConfigByPath() expected a hash, found a ".( $ref || 'scalar' ));
		$result = undef;
	}
	return $result;
}

1;
