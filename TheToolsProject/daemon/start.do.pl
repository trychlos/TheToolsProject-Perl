# @(#) start a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@) Other arguments in the command-line are passed to the run daemon, after the JSON path.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;
use Proc::Background;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Message qw( :all );
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
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
	if( !Mods::Toops::errs()){
		#print Dumper( @ARGV );
		my $proc = Proc::Background->new( "perl $program_path -json $json_path ".join( ' ', @ARGV )) or msgErr( "unable to start '$program_path'" );
		msgOut( "success" ) if $proc;
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
	"json=s"			=> \$opt_json )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );

# the json is mandatory
$daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
msgLog([ "got daemonConfig:", Dumper( $daemonConfig )]);

# must have a listening port
msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
# must have something to run
msgErr( "daemon configuration must define an 'execPath' value, not found" ) if !$daemonConfig->{execPath};

if( !Mods::Toops::errs()){
	doStart();
}

Mods::Toops::ttpExit();
