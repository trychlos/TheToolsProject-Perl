# @(#) stop a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --[no]ignore            ignore the return code if the daemon was not active [${ignore}]
# @(-) --[no]wait              wait for actual termination [${wait}]
# @(-) --timeout=<timeout>     timeout when waiting for termination [${termination}]
# @(-) --sleep=<sleep>         sleep for seconds before exiting [${sleep}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
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

use File::Spec;
use Time::Piece;

use TTP::Daemon;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => '',
	port => '',
	ignore => 'yes',
	wait => 'yes',
	timeout => 60,
	sleep => 0
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_port_set = false;
my $opt_ignore = true;
my $opt_wait = true;
my $opt_timeout = $defaults->{timeout};
my $opt_sleep = $defaults->{sleep};

# -------------------------------------------------------------------------------------------------
# stop the daemon
sub doStop {
	msgOut( "requesting the daemon for termination..." );
	my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
	my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
	my $cmd = "daemon.pl command -nocolored $dummy $verbose -command terminate";
	$cmd .= " -verbose" if $running->verbose();
	if( $opt_json ){
		my $json_path = File::Spec->rel2abs( $opt_json );
		$cmd .= " -json $json_path";
	} elsif( $opt_port_set ){
		$cmd .= " -port $opt_port";
	}
	my $res = `$cmd`;
	# rc is zero if OK
	my $rc = $?;
	if( $res && length $res && !$rc ){
		print "$res";
		my $result = true;
		if( $opt_wait ){
			$result = doWait( $res );
		}
		if( $opt_sleep > 0 ){
			msgOut( "sleeping $opt_sleep sec." );
			sleep $opt_sleep;
		}
		if( $result ){
			msgOut( "success" );
		} else {
			msgErr( "timeout while waiting for daemon termination" );
		}
	} else {
		if( $opt_ignore ){
			msgOut( "no answer from the daemon" );
			msgOut( "success" );
		} else {
			msgWarn( "no answer from the daemon" );
			msgErr( "NOT OK" );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# wait for the daemon actual termination
# return true if the daemon is terminated, false else
sub doWait {
	my ( $answer ) = @_;
	msgOut( "waiting for actual termination..." );
	# get the pid of the answering daemon (first word of each line)
	my @w = split( /\s+/, $answer );
	my $pid = $w[0];
	msgLog( "waiting for '$pid' termination" );
	my $start = localtime;
	my $alive = true;
	my $timedout = false;
	while( $alive && !$timedout ){
		$alive = kill( 0, $pid );
		if( $alive ){
			sleep( 1 );
			my $now = localtime;
			$timedout = ( $now - $start > $opt_timeout );
		}
	}
	return !$alive;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"json=s"			=> \$opt_json,
	"port=i"			=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_port = $opt_value;
		$opt_port_set = true;
	},
	"ignore!"			=> \$opt_ignore,
	"wait!"				=> \$opt_wait,
	"timeout=i"			=> \$opt_timeout,
	"sleep=i"			=> \$opt_sleep )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found port='$opt_port'" );
msgVerbose( "found port_set='".( $opt_port_set ? 'true':'false' )."'" );
msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );
msgVerbose( "found wait='".( $opt_wait ? 'true':'false' )."'" );
msgVerbose( "found timeout='$opt_timeout'" );
msgVerbose( "found sleep='$opt_sleep'" );

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
	my $daemonConfig = TTP::Daemon::getConfigByPath( $opt_json );
	# must have a listening port
	msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
}
#if a port is specified, must have greater than zero
if( $opt_port_set ){
	msgErr( "when specified, addressed port must be regater than zero" ) if $opt_port <= 0;
}

if( !TTP::errs()){
	doStop();
}

TTP::exit();
