# @(#) start a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@) Other arguments in the command-line are passed to the run daemon, after the JSON path.
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
use Proc::Background;

use TTP::Daemon;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => ''
};

my $opt_json = $defaults->{json};

my $daemonConfig = undef;

# -------------------------------------------------------------------------------------------------
# start the daemon
sub doStart {
	my $program_path = $daemonConfig->{execPath};
	my $json_path = File::Spec->rel2abs( $opt_json );
	msgOut( "starting the daemon from '$opt_json'..." );
	msgErr( "$program_path: not found or not readable" ) if ! -r $program_path;
	if( !TTP::errs()){
		#print Dumper( @ARGV );
		my $proc = Proc::Background->new( "perl $program_path -json $json_path ".join( ' ', @ARGV )) or msgErr( "unable to start '$program_path'" );
		msgOut( "success" ) if $proc;
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

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );

# the json is mandatory
$daemonConfig = TTP::Daemon::getConfigByPath( $opt_json );
msgLog([ "got daemonConfig:", Dumper( $daemonConfig )]);

# must have a listening port
msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
# must have something to run
msgErr( "daemon configuration must define an 'execPath' value, not found" ) if !$daemonConfig->{execPath};

if( !TTP::errs()){
	doStart();
}

TTP::exit();
