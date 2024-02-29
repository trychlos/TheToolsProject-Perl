# Copyright (@) 2023-2024 PWI Consulting
#
# Message management.
#
# msgDummy
# msgErr
# msgOut
# msgVerbose
# msgWarn
#	are all functions provided to print a message on the console
#	They all default to also be logged, though this behavior may be disabled in toops/host configuration in key Message/msgOut/withLog
#	They all default to be colorable unless otherwise specified in the command-line (verbs are expected to handle this option)
#	This behavior can too be disabled in toops/host configuration in key Message/msgOut/withColor
#
# msgLog
#	in contrary just add a line to Toops/main.log

package Mods::Message;

use strict;
use warnings;

use Config;
use Data::Dumper;
use Path::Tiny qw( path );
use Sub::Exporter;
use Term::ANSIColor;
use if $Config{osname} eq "MSWin32", "Win32::Console::ANSI";

use Mods::Constants qw( :all );
use Mods::Toops;

Sub::Exporter::setup_exporter({
	exports => [ qw(
		EMERG
		ALERT
		CRIT
		ERR
		WARN
		NOTICE
		INFO
		DEBUG
		DUMMY
		VERBOSE
	)]
});

use constant {
	ALERT => 'ALERT',
	CRIT => 'CRIT',
	DEBUG => 'DEBUG',
	DUMMY => 'DUMMY',
	EMERG => 'EMERG',
	ERR => 'ERR',
	INFO => 'INFO',
	NOTICE => 'NOTICE',
	VERBOSE => 'VERBOSE',
	WARN => 'WARN'
};

=pod
use constant {
	ALERT,
	CRIT,
	DEBUG,
	DUMMY,
	EMERG,
	ERR,
	INFO,
	NOTICE,
	VERBOSE,
	WARN
};
=cut

=pod
my $Order = (
	EMERG,
	ALERT,
	CRIT,
	ERR,
	WARN,
	NOTICE,
	INFO,
	DEBUG
);
=cut

my $Definitions = {
	ALERT => {
	},
	CRIT => {
	},
	DEBUG => {
	},
	DUMMY => {
		color => "cyan",
		marker => "(DUM) ",
		level => INFO,
		key => 'msgDummy'
	},
	EMERG => {
	},
	ERR => {
		color => "bold red",
		marker => "(ERR) ",
		key => 'msgErr'
	},
	INFO => {
		key => 'msgOut'
	},
	NOTICE => {
	},
	VERBOSE => {
		color => "bright_blue",
		marker => "(VER) ",
		level => INFO,
		key => 'msgVerbose'
	},
	WARN => {
		color => "bright_yellow",
		marker => "(WAR) ",
		key => 'msgWarn'
	}
};

# make sure colors are resetted after end of line
$Term::ANSIColor::EACHLINE = EOL;

# -------------------------------------------------------------------------------------------------
# dummy message
# (I):
# - the message to be printed (usually the command to be run in dummy mode)
sub msgDummy {
	my $TTPVars = Mods::Toops::TTPVars();
	if( $TTPVars->{run}{dummy} ){
		_printMsg({
			msg => shift,
			level => DUMMY
		});
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# Error message (should always be logged event if TTP let the site integrator disable that)
# (I):
# - the message to be printed on STDERR
# (O):
# - increments the exit code
sub msgErr {
	# let have a stack trace
	#Mods::Toops::stackTrace();
	# and send the message
	_printMsg({
		msg => shift,
		level => ERR,
		handle => \*STDERR
	});
	my $TTPVars = Mods::Toops::TTPVars();
	$TTPVars->{run}{exitCode} += 1;
}

# -------------------------------------------------------------------------------------------------
# prefix and log a message
# (I):
# - the message(s) to be written in Toops/main.log
#   may be a scalar (a string) or an array ref of scalars
sub msgLog {
	my $msg = shift;
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $line ( split( /[\r\n]/, @{$msg} )){
			chomp $line;
			msgLog( $line );
		}
	} elsif( !$ref ){
		_msgLogAppend( _msgPrefix().$msg );
	} else {
		msgWarn( "Message::msgLog() unmanaged type '$ref' for '$msg'" );
		Mods::Toops::stackTrace();
	}
}

# -------------------------------------------------------------------------------------------------
# log an already prefixed message
# do not try to write in logs while they are not initialized
# the host config is silently reevaluated on each call to be sure we are writing in the logs of the day

sub _msgLogAppend {
	my ( $msg ) = @_;
	my $TTPVars = Mods::Toops::TTPVars();
	if( $TTPVars->{run}{logsMain} ){
		my $host = uc hostname;
		my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
		my $line = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%5N' )." $host $username $msg";
		path( $TTPVars->{run}{logsMain} )->append_utf8( $line.EOL );
	}
}

=pod
# -------------------------------------------------------------------------------------------------
# Also logs msgOut or msgVerbose (or others) messages depending of:
# - whether the passed-in options have a truethy 'withLog'
# - whether the corresponding option is set in Toops (resp. host) configuration
# - defaulting to truethy (Toops default is to log everything)
sub _msgLogIf {
	# the ligne which has been {config}{ed
	my $msg = shift;
	# the caller options - we search here for a 'withLog' option
	my $opts = shift || {};
	# the key in site configuration
	my $key = shift || '';
	# where default is true
	my $TTPVars = Mods::Toops::TTPVars();
	my $withLog = true;
	$withLog = $TTPVars->{config}{toops}{$key} if $key and exists $TTPVars->{config}{toops}{$key};
	$withLog = $opts->{withLog} if exists $opts->{withLog};
	Mods::Message::_msgLogAppend( $msg ) if $withLog;
}
=cut

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (I):
# - the message to be outputed
sub msgOut {
	_printMsg({
		msg => shift
	});
}

# -------------------------------------------------------------------------------------------------
# Compute the message prefix, including a trailing space
sub _msgPrefix {
	my $prefix = '';
	my $TTPVars = Mods::Toops::TTPVars();
	if( $TTPVars->{run}{command}{basename} ){
		$prefix = "[$TTPVars->{run}{command}{basename}";
		$prefix .= ' '.$TTPVars->{run}{verb}{name} if $TTPVars->{run}{verb}{name};
		$prefix.= '] ';
	} elsif( $TTPVars->{run}{daemon}{name} ){
		$prefix = "[$TTPVars->{run}{daemon}{name}";
		$prefix .= ' '.$TTPVars->{run}{daemon}{add} if $TTPVars->{run}{daemon}{add};
		$prefix.= '] ';
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (I):
# - the message to be outputed
sub msgVerbose {
	my $msg = shift;
	# be verbose to console ?
	my $verbose = false;
	$verbose = $TTPVars->{run}{verbose} if exists( $TTPVars->{run}{verbose} );
	$verbose = $opts->{verbose} if exists( $opts->{verbose} );
	_printMsg({
		msg => $msg,
		level => VERBOSE,
		withConsole => $verbose
	});
}

# -------------------------------------------------------------------------------------------------
# Warning message - always logged
# (E):
# - the single warning message
sub msgWarn {
	_printMsg({
		msg => shift,
		level => WARN
	});
}

# -------------------------------------------------------------------------------------------------
# print a message to stdout, and log
# argument is a single hash with following keys:
# - msg: the single line to be printed, defaulting to ''
# - level: the requested message level, defaulting to INFO
# - handle, the output handle, defaulting to STDOUT
# - withConsole: whether to output to the console, defaulting to true
sub _printMsg {
	my ( $args ) = @_;
	$args //= {};
	my $line = '';
	my $var = undef;
	# have a prefix ?
	my $withPrefix = true;
	$line .= Mods::Toops::_msgPrefix() if $withPrefix;
	# have a level marker ?
	my $level = INFO;
	$level = $args->{level} if exists $args->{level};
	$line .= $Definitions->{$level}{marker} if exists $Definitions->{$level}{marker};
	$line .= $args->{msg} if exists $args->{msg};
	# writes in log ?
	my $withLog = true;
	$var = Mods::Toops::var( 'Message',  $Definitions->{$level}{key}, 'withLog' ) if exists $Definitions->{$level}{key};
	$withLog = $var if defined $var;
	Mods::Message::_msgLogAppend( $line ) if $withLog;
	# output to the console ?
	my $withConsole = true;
	$withConsole = $args->{withConsole} if exists $args->{withConsole};
	if( $withConsole ){
		# print a colored line ?
		# global runtime option is only considered if not disabled in toops/host configuration
		my $withColor = true;
		$var = undef;
		$var = Mods::Toops::var( 'Message',  $Definitions->{$level}{key}, 'withColor' ) if exists $Definitions->{$level}{key};
		$withColor = $var if defined $var;
		$withColor = $TTPVars->{run}{colored} if $withColor;
		my $colorstart = $withColor && exists( $Definitions->{$level}{color} ) ? color( $Definitions->{$level}{color} ) : '';
		my $colorend = $withColor && exists( $Definitions->{$level}{color} ) ? color( 'reset' ) : '';
		# print on which handle ?
		my $handle = \*STDOUT;
		$handle = $args->{handle} if exists $args->{handle};
		print $handle "$colorstart$line$colorend".EOL;
	}
}

1;
