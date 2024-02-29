# Copyright (@) 2023-2024 PWI Consulting
#
# Message management.

package Mods::Message;

use strict;
use warnings;

use Config;
use Data::Dumper;
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
		NONE
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
	NONE => 'NONE',
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
	NONE,
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
	DEBUG,
	NONE
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
		level => INFO
	},
	EMERG => {
	},
	ERR => {
		color => "bold red",
		marker => "(ERR) "
	},
	INFO => {
	},
	NONE => {
	},
	NOTICE => {
	},
	VERBOSE => {
		color => "bright_blue",
		marker => "(VER) ",
		level => INFO
	},
	WARN => {
		color => "bright_yellow",
		marker => "(WAR) "
	}
};

# make sure colors are resetted after end of line
$Term::ANSIColor::EACHLINE = EOL;

# ------------------------------------------------------------------------------------------------
# print a message to stdout, and log
# argument is a single hash with following keys:
# - msg: the line to be printed, defaulting to ''
# - level: the requested message level, defaulting to NONE
# - handle, the output handle, defaulting to STDOUT
# - withConsole: whether to output to the console, defaulting to true
# - withPrefix: defaulting to true
# - withLog: defaulting to true
# - withColor: defaulting to true
sub print {
	my ( $args ) = @_;
	$args //= {};
	my $line = '';
	# have a prefix ?
	my $withPrefix = true;
	$withPrefix = $args->{withPrefix} if exists $args->{withPrefix};
	$line .= Mods::Toops::msgPrefix() if $withPrefix;
	# have a level marker ?
	my $level = NONE;
	$level = $args->{level} if exists $args->{level};
	$line .= $Definitions->{$level}{marker} if exists $Definitions->{$level}{marker};
	$line .= $args->{msg} if exists $args->{msg};
	# writes in log ?
	my $withLog = true;
	$withLog = $args->{withLog} if exists $args->{withLog};
	Mods::Toops::msgLogAppend( $line ) if $withLog;
	# output to the console ?
	my $withConsole = true;
	$withConsole = $args->{withConsole} if exists $args->{withConsole};
	if( $withConsole ){
		# print a colored line ?
		my $withColor = true;
		$withColor = $args->{withColor} if exists $args->{withColor};
		my $colorstart = $withColor && exists( $Definitions->{$level}{color} ) ? color( $Definitions->{$level}{color} ) : '';
		my $colorend = $withColor && exists( $Definitions->{$level}{color} ) ? color( 'reset' ) : '';
		# print on which handle ?
		my $handle = \*STDOUT;
		$handle = $args->{handle} if exists $args->{handle};
		print $handle "$colorstart$line$colorend".EOL;
	}
}

1;
