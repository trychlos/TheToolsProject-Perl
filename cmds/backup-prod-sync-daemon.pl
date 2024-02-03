#!perl
#!/usr/bin/perl
#
# This runs as a daemon to monitor the backups in the live production
#
# Command-line arguments:
# - the full path to the JSON configuration file
#
# Copyright (@) 2023-2024 PWI Consulting

use strict;
use warnings;
use feature qw( switch );

use Data::Dumper;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Toops;

# auto-flush on socket
$| = 1;

my $commands = {
	#help => \&help,
};

# -------------------------------------------------------------------------------------------------
# do its work
sub works {
}

# =================================================================================================
# MAIN
# =================================================================================================

Mods::Daemon::daemonInitToops( $0 );
my $TTPVars = Mods::Toops::TTPVars();
my $daemonConfig = Mods::Daemon::getConfigByPath( $ARGV[0] );
my $socket = Mods::Daemon::daemonCreateListeningSocket( $daemonConfig );

while( !$TTPVars->{run}{daemon}{terminating} ){
	my $res = Mods::Daemon::daemonListen( $socket, $commands );
	works();
	sleep( 5 );
}

Mods::Toops::msgLog( "terminating" );
Mods::Toops::ttpExit();
