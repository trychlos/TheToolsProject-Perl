# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 2003-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2024 PWI Consulting
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
# In the command 'ttp.pl' in the 'ttp.pl vars --logsRoot', we call:
# - a 'command' the first executed word, here: 'ttp.pl'
# - a 'verb' the second word, here 'vars'.
#
# Verbs are executed in this Command context.

package TTP::Command;

use base qw( TTP::Base );
our $VERSION = '1.00';

use strict;
use warnings;

use Carp;
use Config;
use Data::Dumper;
use Getopt::Long;
use Role::Tiny::With;
use Try::Tiny;
use vars::global qw( $ttp );

with 'TTP::Findable', 'TTP::Optionable', 'TTP::Runnable';

use TTP;
use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
	# reserved words: the commands must be named outside of this array
	#  either because they are folders of the Toops installation tree
	reservedWords => [
		'bin',
		'libexec',
		'Mods',
		'Toops',
		'TTP'
	],
	verbSufix => '.do.pl',
	commentPre => '^# @\(#\) ',
	commentPost => '^# @\(@\) ',
	commentUsage => '^# @\(-\) ',
	verbSed => '\.do\.pl',
};

### Private methods

# -------------------------------------------------------------------------------------------------
# returns the available verbs for the current command
# (O):
# - a ref to an array of full paths of available verbs for the current command

sub _getVerbs {
	my ( $self ) = @_;

	my @verbs = ();
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	foreach my $it ( @roots ){
		my $dir = File::Spec->catdir( $it, $self->runnableBNameShort());
		push @verbs, glob( File::Spec->catdir( $dir, "*".$Const->{verbSufix} ));
	}

	return @verbs;
}

# -------------------------------------------------------------------------------------------------
# Display the command one-liner help
# (I):
# - the full path to the command
# - an optional options hash with following keys:
#   > prefix: the line prefix, defaulting to ''

sub _helpCommandOneline {
	my ( $self, $command_path, $opts ) = @_;

	$opts //= {};
	my $prefix = '';
	$prefix = $opts->{prefix} if exists( $opts->{prefix} );
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $command_path );
	my @commandHelp = TTP::grepFileByRegex( $command_path, $Const->{commentPre} );
	print "$prefix$bname: $commandHelp[0]".EOL;
}

# -------------------------------------------------------------------------------------------------
# command initialization
# (I]:
# - none
# (O):
# - this object

sub _init {
	my ( $self ) = @_;

	# make sure the command is not a reserved word
	my $command = $self->runnableBNameShort();
	if( grep( /^$command$/, @{$Const->{reservedWords}} )){
		msgErr( "command '$command' is a Toops reserved word. Aborting." );
		ttpExit();
	}

	return $self;
}

### Public methods

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the command name
# (I]:
# - none
# (O):
# - the command e.g. 'ttp.pl'

sub command {
	my ( $self ) = @_;

	return $self->runnableBNameFull();
}

# -------------------------------------------------------------------------------------------------
# Command help
# Display the command help as:
# - a one-liner from the command itself
# - and the one-liner help of each available verb
# (I]:
# - none
# (O):
# - this object

sub commandHelp {
	my ( $self ) = @_;

	msgVerbose( "helpCommand()" );
	# display the command one-line help
	$self->_helpCommandOneline( $self->runnablePath());
	# display each verb one-line help
	my @verbs = $self->_getVerbs();
	my $verbsHelp = {};
	foreach my $it ( @verbs ){
		my @fullHelp = TTP::grepFileByRegex( $it, $Const->{commentPre}, { warnIfSeveral => false });
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $it );
		my $verb = $file;
		$verb =~ s/$Const->verbSed}$//;
		$verbsHelp->{$verb} = $fullHelp[0];
	}
	# verbs are displayed alpha sorted
	@verbs = keys %{$verbsHelp};
	my @sorted = sort @verbs;
	foreach my $it ( @sorted ){
		print "  $it: $verbsHelp->{$it}".EOL;
	}

	return $self;
}

# -------------------------------------------------------------------------------------------------
# run the command
# (I]:
# - none
# (O):
# - this object

sub run {
	my ( $self ) = @_;

	try {
		# first argument is supposed to be the verb
		my @command_args = @ARGV;
		$self->{_verb} = {};
		if( scalar @command_args ){
			my $verb = shift( @command_args );
			$self->{_verb}{args} = \@command_args;
			$self->runnableSetQualifier( $verb );

			# as verbs are written as Perl scripts, they are dynamically ran from here in the context of 'self'
			# + have direct access to 'ttp' entry point
			local @ARGV = @command_args;
			our $running = $ttp->running();
			$self->{_verb}{path} = $self->find({ spec => [ $self->runnableBNameShort(), $verb.$Const->{verbSufix} ]});
			if( -f $self->{_verb}{path} ){
				unless( defined do $self->{_verb}{path} ){
					msgErr( "do $self->{_verb}{path}: ".( $! || $@ ));
				}
			} else {
				msgErr( "script not found or not readable: '$self->{_verb}{path}' (most probably, '$self->{_verb}{name}' is not a valid verb)" );
			}
		} else {
			$self->commandHelp();
			ttpExit();
		}
	} catch {
		msgVerbose( "catching exit" );
		ttpExit();
	};

	ttpExit();
	return $self;
}

# -------------------------------------------------------------------------------------------------
# Getter
# Returns the verb name
# (I]:
# - none
# (O):
# - the verb, e.g. 'vars'

sub verb {
	my ( $self ) = @_;

	return $self->runnableQualifier();
}

# -------------------------------------------------------------------------------------------------
# Verb help
# Display the full verb help
# - the one-liner help of the command
# - the full help of the verb as:
#   > a pre-usage help
#   > the usage of the verb
#   > a post-usage help
# (I):
# - a hash which contains default values
# (O):
# - this object

sub verbHelp {
	my ( $self, $defaults ) = @_;

	msgVerbose( "helpVerb()" );
	# display the command one-line help
	$self->_helpCommandOneline( $self->runnablePath());
	# verb pre-usage
	my @verbHelp = TTP::grepFileByRegex( $self->{_verb}{path}, $Const->{commentPre}, { warnIfSeveral => false });
	my $verbInline = '';
	if( scalar @verbHelp ){
		$verbInline = shift @verbHelp;
	}
	print "  ".$self->verb().": $verbInline".EOL;
	foreach my $line ( @verbHelp ){
		print "    $line".EOL;
	}
	# verb usage
	@verbHelp = TTP::grepFileByRegex( $self->{_verb}{path}, $Const->{commentUsage}, { warnIfSeveral => false });
	if( scalar @verbHelp ){
		print "    Usage: ".$self->command()." ".$self->verb()." [options]".EOL;
		print "    where available options are:".EOL;
		foreach my $line ( @verbHelp ){
			$line =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "      $line".EOL;
		}
	}
	# verb post-usage
	@verbHelp = TTP::grepFileByRegex( $self->{_verb}{path}, $Const->{commentPost}, { warnIfNone => false, warnIfSeveral => false });
	if( scalar @verbHelp ){
		foreach my $line ( @verbHelp ){
			print "    $line".EOL;
		}
	}

	return $self;
}

### Class methods

# -------------------------------------------------------------------------------------------------
# Constructor
# (I]:
# - the TTP EP entry point
# (O):
# - this object

sub new {
	my ( $class, $ttp, $args ) = @_;
	$class = ref( $class ) || $class;
	$args //= {};
	my $self = $class->SUPER::new( $ttp, $args );
	bless $self, $class;

	# command initialization
	$self->_init();

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

1;

__END__
