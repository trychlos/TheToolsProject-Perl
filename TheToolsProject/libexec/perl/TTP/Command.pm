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
	#  or because they are first level key in TTPVars (thus preventing to have a 'command' object at this first level)
	reservedWords => [
		'bin',
		'libexec',
		'Mods',
		'Toops',
		'TTP'
	],
	verbSufix => '.do.pl',
};

### Private methods

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
# command help
# (I]:
# - none
# (O):
# - this object

sub commandHelp {
	my ( $self ) = @_;

	print "commandHelp()".EOL;

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
			if( scalar( @command_args )){
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
				$self->verbHelp();
				ttpExit();
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
# verb help
# (I]:
# - none
# (O):
# - this object

sub verbHelp {
	my ( $self ) = @_;

	print "verbHelp()".EOL;
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
