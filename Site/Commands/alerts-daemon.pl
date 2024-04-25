#!perl
#!/usr/bin/perl
# @(#) Monitor the json alert files dropped in the alerts directory.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
#
# @(@) This script is expected to be run as a daemon, started via a 'daemon.pl start -json <filename.json>' command.
#
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
# This script is mostly written like a TTP verb but is not. This is an example of how to take advantage of TTP
# to write your own (rather pretty and efficient) daemon.
# Just to be sure: this makes use of Toops, but is not part itself of Toops (though a not so bad example of application).

use strict;
use warnings;

use Data::Dumper;
use File::Find;
use Getopt::Long;
use Time::Piece;

use TTP;
use TTP::Constants qw( :all );
use TTP::Daemon;
use TTP::Message qw( :all );
use TTP::Path;
use vars::global qw( $ttp );

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => ''
};

my $opt_json = $defaults->{json};

my $commands = {
	#help => \&help,
};

#my $TTPVars = TTP::Daemon::init();
#my $daemon = undef;
my $daemon = TTP::Daemon->init();

# scanning for new elements
my $lastScanTime = 0;
my $first = true;
my @previousScan = ();
my @runningScan = ();

# -------------------------------------------------------------------------------------------------
# new alert
# should never arrive as all alerts should also be sent through MQTT bus which is the preferred way of dealing with these alerts
sub doWithNew {
	my ( @newFiles ) = @_;
	foreach my $file ( @newFiles ){
		msgVerbose( "new alert '$file'" );
		my $data = TTP::jsonRead( $file );
	}
}

# -------------------------------------------------------------------------------------------------
# we find less files in this iteration than in the previous - maybe some files have been purged, deleted
# moved, or we have a new directory, or another reason - just reset and restart over
sub varReset {
	msgVerbose( "varReset()" );
	@previousScan = ();
}

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.
sub wanted {
	return unless /\.json$/;
	push( @runningScan, $File::Find::name );
}

# -------------------------------------------------------------------------------------------------
# do its work
sub works {
	@runningScan = ();
	find( \&wanted, $daemon->{config}{monitoredDir} );
	if( scalar @runningScan < scalar @previousScan ){
		varReset();
	} elsif( $first ){
		$first = false;
		@previousScan = sort @runningScan;
	} elsif( scalar @runningScan > scalar @previousScan ){
		my @sorted = sort @runningScan;
		my @tmp = @sorted;
		my @newFiles = splice( @tmp, scalar @previousScan, scalar @runningScan - scalar @previousScan );
		doWithNew( @newFiles );
		@previousScan = @sorted;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"json=s"			=> \$opt_json )){

		msgOut( "try '".$daemon->runnableBNameFull()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $daemon->help()){
	$daemon->helpExtern( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );

msgErr( "'--json' option is mandatory, not specified" ) if !$opt_json;

if( !TTP::errs()){
	#$daemon = TTP::Daemon::run( $opt_json );
	$daemon->path( $opt_json );
}
# more deeply check arguments
# - the daemon configuration must have monitoredDir key
if( !TTP::errs()){
	if( exists( $daemon->{config}{monitoredDir} )){
		msgVerbose( "monitored dir '$daemon->{config}{monitoredDir}' successfully found in daemon configuration file" );
	} else {
		msgErr( "'monitoredDir' must be specified in daemon configuration, not found" );
	}
}
if( TTP::errs()){
	TTP::exit();
}

my $scanInterval = 10;
$scanInterval = $daemon->{config}{scanInterval} if exists $daemon->{config}{scanInterval} && $daemon->{config}{scanInterval} >= $scanInterval;

my $sleepTime = TTP::Daemon::getSleepTime(
	$daemon->{listenInterval},
	$scanInterval
);

msgVerbose( "sleepTime='$sleepTime'" );
msgVerbose( "scanInterval='$scanInterval'" );

while( !$daemon->{terminating} ){
	my $res = TTP::Daemon::daemonListen( $daemon, $commands );
	my $now = localtime->epoch;
	if( $now - $lastScanTime >= $scanInterval ){
		works();
		$lastScanTime = $now;
	}
	sleep( $sleepTime );
}

TTP::Daemon::terminate( $daemon );
