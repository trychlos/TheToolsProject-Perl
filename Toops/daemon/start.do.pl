# @(#) start a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;
use Proc::Background;

use Mods::Constants;
use Mods::Daemon;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
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
	Mods::Toops::msgOut( "starting the daemon from '$opt_json'..." );
	Mods::Toops::msgErr( "$program_path: not found or not readable" ) if ! -r $program_path;
	if( !Mods::Toops::errs()){
		my $proc = Proc::Background->new( "perl $program_path $json_path" ) or Mods::Toops::msgErr( "unable to start '$program_path'" );
		Mods::Toops::msgOut( "success" ) if $proc;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"json=s"			=> \$opt_json )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found json='$opt_json'" );

# the json is mandatory
$daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
# must have a listening port
Mods::Toops::msgErr( "JSON configuration must define a daemon 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
# must have something to run
Mods::Toops::msgErr( "JSON configuration must define a daemon 'execPath' value, not found" ) if !$daemonConfig->{execPath};

if( !Mods::Toops::errs()){
	doStart();
}

Mods::Toops::ttpExit();