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
# - execPath: the full path to the program to be executed as the main code of the daemon
#
# Also the daemon writer mmust be conscious of the dynamic character of TheToolsProject.
# In particular and at least, many output directories (logs, temp files and so on) may be built on a daily basis.
# So your configuration files must be periodically re-evaluated.
# This 'Daemon' class takes care of reevaluating both the host and the daemon configurations
# on each listenInterval.
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

with 'TTP::Enableable', 'TTP::Findable', 'TTP::JSONable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::MQTT;

use constant {
	BUFSIZE => 4096,
	MIN_LISTEN_INTERVAL => 1,
	DEFAULT_LISTEN_INTERVAL => 5,
	MIN_ADVERTIZE_INTERVAL => 10,
	DEFAULT_ADVERTIZE_INTERVAL => 60,
	OFFLINE => "offline"
};

# auto-flush on socket
$| = 1;

my $Const = {
	# the commands the class manages for all daemons
	commonCommands => {
		help => \&do_help,
		status => \&do_status,
		terminate => \&do_terminate
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

### Private methods

### Public methods

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon is enabled (as a reason to not be successful)
# (I):
# - none
# (O):
# - returns true|false

sub enabled {
	my ( $self ) = @_;

	return $self->{_enabled};
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
# Returns the canonical name of the daemon which happens to be the basename of its configuration file
# (I):
# - none
# (O):
# - returns the name of the daemon, or undef if the initialization has not been successful

sub name {
	my ( $self ) = @_;

	return undef if !$self->success();
	
	my $path = $self->jsonPath();
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $path );

	return $bname;
}

# ------------------------------------------------------------------------------------------------
# Start the daemon
# (I):
# - none
# (O):
# - returns true|false

sub start {
	my ( $self ) = @_;

	my $program = $self->execPath();
	msgErr( "daemon configuration must define an 'execPath' value, not found" ) if !$program;
	msgErr( "execPath='$program' not found or not readable" ) if ! -r $program;

	if( !TTP::errs()){
		my $proc = Proc::Background->new( "perl $program -json ".$self->jsonPath()." ".join( ' ', @ARGV ));
		if( $proc ){
			$self->{_proc} = $proc;
			$self->{_started} = true;
		} else {
			msgErr( "unable to start '$program'" );
		}
	}

	return $self->{_started};
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon has been successfully started
# (I):
# - none
# (O):
# - returns true|false

sub started {
	my ( $self ) = @_;

	return $self->{_started};
}

# ------------------------------------------------------------------------------------------------
# Returns whether the daemon configuration file has been successfully loaded and evaluated
# (I):
# - none
# (O):
# - returns true|false

sub success {
	my ( $self ) = @_;

	return $self->{_success};
}

### Class methods

# ------------------------------------------------------------------------------------------------
# Returns the list of directories in which we may find daemons configuration files
# (I):
# - none
# (O):
# - returns the list of directories which may contain the JSON daemons configuration files as
#   an array ref

sub configurationsDirs {
	my ( $class ) = @_;
	$class = ref( $class ) || $class;

	my $dirs = [];
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $specs = $class->dirs();
	foreach my $it ( @roots ){
		foreach my $sub ( @{$specs} ){
			push( @{$dirs}, File::Spec->catdir( $it, $sub ));
		}
	}

	return $dirs;
}

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
# Constructor
# We never abort if we cannot find or load the daemon configuration file. We set instead the 'success'
# flag that the caller MUST test.
# (I]:
# - the TTP EP entry point
# - an argument object with following keys:
#   > path: the absolute path to the JSON configuration file
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp );
	bless $self, $class;

	$self->{_success} = false;
	$self->{_enabled} = true;
	$self->{_started} = false;

	# if a path is specified, then we try to load it
	# this is after that raw load that we can test for enability
	if( $args->{path} ){
		$self->{_success} = $self->jsonLoad({ path => $args->{path} });
		if( $self->{_success} ){
			my $data = $self->jsonData();
			$self->{_enabled} = $data->{enabled} if exists $data->{enabled};
			if( !$self->{_enabled} ){
				msgVerbose( __PACKAGE__."::new() path='$args->{path}' enabled=false" );
				$self->{_success} = false;
			}
		}
	}

	# evaluate the data if success
	if( $self->{_success} ){
		$self->evaluate();
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
# build and returns the last will MQTT message for the daemon
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
	my $TTPVars = TTP::TTPVars();
	return "running since $ttp->{run}{command}{started}";
}

# ------------------------------------------------------------------------------------------------
sub _topic {
	my ( $name ) = @_;
	my $topic = TTP::host();
	$topic .= "/daemon";
	$topic .= "/$name";
	$topic .= "/status";
	return $topic;
}

# ------------------------------------------------------------------------------------------------
# returns common commands
# (useful when the daeon wants override a standard answer)
sub commonCommands {
	return $Const->{commonCommands};
}

# ------------------------------------------------------------------------------------------------
# the daemon advertize of its status every 'advertizeInterval' seconds (defaults to 60)
sub daemonAdvertize {
	my ( $daemon ) = @_;
	my $now = localtime->epoch;
	if( !$daemon->{lastAdvertized} || $now-$daemon->{lastAdvertized} >= $daemon->{advertizeInterval} ){
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
# the daemon answers to the client
# the answer string is expected to be '\n'-terminated
# we send the answer prefixing each line by the daemon pid
sub daemonAnswer {
	my ( $daemon, $req, $answer ) = @_;
	msgLog( "answering '$answer' and ok-ing" );
	foreach my $line ( split( /[\r\n]+/, $answer )){
		$req->{socket}->send( "$$ $line\n" );
	}
	$req->{socket}->send( "$$ OK\n" );
	$req->{socket}->shutdown( SHUT_WR );
}

# ------------------------------------------------------------------------------------------------
# the daemon deals with the received command
# - we are able to answer here to 'help', 'status' and 'terminate' commands and the daemon doesn't need to declare them.
# (I):
# - the Daemon object
# - the received request_method
# - the hash of the daemon specific commands
sub daemonCommand {
	my ( $daemon, $req, $commands ) = @_;
	my $answer = undef;
	# first try to execute a specific daemon command, passing it the received request
	if( $commands->{$req->{command}} ){
		$answer = $commands->{$req->{command}}( $req );
	# else ty to execute a standard command
	} elsif( $Const->{commonCommands}{$req->{command}} ){
		$answer = $Const->{commonCommands}{$req->{command}}( $daemon, $req, $commands );
	# else the command is just unknowned
	} else {
		$answer = "unknowned command '$req->{command}'";
	}
	return $answer;
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
	# -> toops+site and execution host configurations
	TTP::ttpEvaluate();
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
		msgLog( "received '$data' from '$result->{peerhost}':'$result->{peeraddr}':'$result->{peerport}'" );
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
# answers to 'help' command
sub do_help {
	my ( $daemon, $req, $commands ) = @_;
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
# answers to 'status' command with:
# - running since yyyy-mm-dd hh:mi:ss
# - json: 
# - listeningPort:
# - pid:
sub do_status {
	my ( $daemon, $req, $commands ) = @_;
	my $answer = _running().EOL;
	$answer .= "json: $daemon->{json}".EOL;
	$answer .= "listeningPort: $daemon->{config}{listeningPort}".EOL;
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# answers to 'terminate' command
sub do_terminate {
	my ( $daemon, $req, $commands ) = @_;
	$daemon->{terminating} = true;
	my $answer = "";
	return $answer;
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
	$result = TTP::evaluate( $result ) if $result;
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
# initialize The Tools Project to be usable by a running daemon
# (I):
# - an optional options hash ref with following keys:
#   > name: a qualifiant name to be displayed on prefixed log lines, at the same place than the the verb name
# (O):
# returns the TTPVars variable

sub init {
	my ( $opts ) = @_;
	$opts //= {};

	# init TTP
	TTP::init();
	my $TTPVars = TTP::TTPVars();

	# initialize TTPVars data to have a pretty log
	my( $vol, $dirs, $file ) = File::Spec->splitpath( $0 );
	$ttp->{run}{command}{path} = $0;
	$ttp->{run}{command}{started} = Time::Moment->now;
	$ttp->{run}{command}{args} = \@ARGV;
	$ttp->{run}{command}{basename} = $file;
	$file =~ s/\.[^.]+$//;
	$ttp->{run}{command}{name} = $file;
	$ttp->{run}{help} = scalar @ARGV ? false : true;

	# set the qualificant additional name
	my $name = "";
	$name = $opts->{name} if $opts->{name};
	$ttp->{run}{verb}{name} = $name if $name;

	return $TTPVars;
}

# ------------------------------------------------------------------------------------------------
# initialize the TTP daemon
# (I):
# - the json configuration filename
# (O):
# returns the daemon object with:
# - json: the json configuration file path
# - config: its json evaluated configuration (and reevaluated at each listenInterval)
# - socket: the created listening socket
# - sleep: the sleep interval
# - listenInterval: computed runtime value
sub run {
	my ( $json ) = @_;
	my $daemon = undef;

	# get and check the daemon configuration
	my ( $jvol, $jdirs, $jfile ) = File::Spec->splitpath( $json );
	$jfile =~ s/\.[^.]+$//;
	my $raw = getRawConfigByPath( $json );
	my $config = $raw ? getEvaluatedConfig( $raw ) : undef;
	# listening port
	if( !$config->{listeningPort} ){
		msgErr( "daemon configuration must define a 'listeningPort' value, not found" );
	}
	# listen interval
	my $listenInterval = DEFAULT_LISTEN_INTERVAL;
	if( $config && exists( $config->{listenInterval} )){
		if( $config->{listenInterval} < MIN_LISTEN_INTERVAL ){
			msgVerbose( "defined listenInterval=$config->{listenInterval} less than minimum accepted ".MIN_LISTEN_INTERVAL.", ignored" );
		} else {
			$listenInterval = $config->{listenInterval};
		}
	}
	# advertize interval
	my $advertizeInterval = DEFAULT_ADVERTIZE_INTERVAL;
	if( exists( $config->{advertizeInterval} )){
		if( $config->{advertizeInterval} < MIN_ADVERTIZE_INTERVAL ){
			msgVerbose( "defined advertizedInterval=$config->{advertizeInterval} less than minimum accepted ".MIN_ADVERTIZE_INTERVAL.", ignored" );
		} else {
			$advertizeInterval = $config->{advertizeInterval};
		}
	}
	if( !TTP::errs()){
		msgVerbose( "listeningPort='$config->{listeningPort}' listenInterval='$listenInterval' advertizeInterval='$advertizeInterval'" );
	}

	# create a listening socket
	my $socket = undef;
	if( !TTP::errs()){
		$socket = new IO::Socket::INET(
			LocalHost => '0.0.0.0',
			LocalPort => $config->{listeningPort},
			Proto => 'tcp',
			Type => SOCK_STREAM,
			Listen => 5,
			ReuseAddr => true,
			Blocking => false,
			Timeout => 0
		) or msgErr( "unable to create a listening socket: $!" );
	}

	# connect to MQTT communication bus if the host is configured for
	my $mqtt = undef;
	if( !TTP::errs()){
		$mqtt = TTP::MQTT::connect({
			will => _lastwill( $jfile )
		});
	}
	if( !TTP::errs()){
		$SIG{INT} = sub { $socket->close(); TTP::exit(); };
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
# terminate the daemon, gracefully closing all opened connections
sub terminate {
	my ( $daemon ) = @_;

	# close MQTT connection
	TTP::MQTT::disconnect( $daemon->{mqtt} ) if $daemon->{mqtt};

	# close TCP connection
	$daemon->{socket}->close();

	# have a log line
	msgLog( "terminating" );

	# and quit the program
	TTP::exit();
}

1;
