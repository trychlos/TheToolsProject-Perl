# @(#) stop a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --ignore                ignore the return code if the daemon is not active [${ignore}]
# @(-) --wait=<wait>           wait for seconds before exiting [${wait}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use Mods::Constants;
use Mods::Daemon;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	port => '',
	ignore => 'no',
	wait => 0
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_ignore = false;
my $opt_wait = $defaults->{wait};

# -------------------------------------------------------------------------------------------------
# stop the daemon
sub doStop {
	Mods::Toops::msgOut( "requesting the daemon for termination..." );
	my $cmd = "daemon.pl command -command terminate";
	$cmd .= " -verbose" if $TTPVars->{run}{verbose};
	if( $opt_json ){
		my $json_path = File::Spec->rel2abs( $opt_json );
		$cmd .= " -json $json_path";
	}
	$cmd .= " -port $opt_port" if $opt_port != -1;
	$cmd .= " -ignore" if $opt_ignore;
	my $res = `$cmd`;
	if( $res && length $res && !$? ){
		print "$res";
		if( $opt_wait > 0 ){
			Mods::Toops::msgVerbose( "sleeping $opt_wait sec." );
			sleep $opt_wait;
		}
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgWarn( "no answer from the daemon" );
		Mods::Toops::msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"json=s"			=> \$opt_json,
	"port=i"			=> \$opt_port,
	"ignore!"			=> \$opt_ignore,
	"wait=i"			=> \$opt_wait )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found json='$opt_json'" );
Mods::Toops::msgVerbose( "found port='$opt_port'" );
Mods::Toops::msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found wait='$opt_wait'" );

# either the json or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	Mods::Toops::msgErr( "one of '--json' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	Mods::Toops::msgErr( "one of '--json' or '--port' options must be specified, both were found" );
}
#if a json is specified, must have a listeningPort
if( $opt_json ){
	my $daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
	# must have a listening port
	Mods::Toops::msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
}

if( !Mods::Toops::errs()){
	doStop();
}

Mods::Toops::ttpExit();