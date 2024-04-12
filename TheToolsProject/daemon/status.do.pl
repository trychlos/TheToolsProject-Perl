# @(#) get the running status of a TTP daemon
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<name>           the JSON file which characterizes this daemon [${json}]
# @(-) --bname=<name>          the JSON file basename [${bname}]
# @(-) --port=<port>           the port number to address [${port}]
# @(-) --[no]http              whether to publish an HTTP telemetry [${http}]
#
# @(@) The Tools Project is able to manage any daemons with these very same verbs.
# @(@) Each separate daemon is characterized by its own JSON properties which uniquely identifies it from the TTP point of view.
# @(@) This script accepts other options, after a '--' double dash, which will be passed to 'telemetry.pl publish' verb.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Daemon;
use Mods::Message qw( :all );
use Mods::Path;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	bname => '',
	port => '',
	http => 'no'
};

my $opt_json = $defaults->{json};
my $opt_port = -1;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# get a daemon status
sub doStatus {
	msgOut( "requesting the daemon for its status..." );
	my $dummy =  $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose =  $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
	my $cmd = "daemon.pl command -nocolored $dummy $verbose -command status";
	if( $opt_json ){
		my $json_path = File::Spec->rel2abs( $opt_json );
		$cmd .= " -json $json_path";
	}
	$cmd .= " -port $opt_port" if $opt_port != -1;
	my $res = `$cmd`;
	my $result = ( $res && length $res && $? == 0 );
	if( $opt_http ){
		my $value = $result ? "1" : "0";
		my $command = "telemetry.pl publish -value $value ".join( ' ', @ARGV )." -nomqtt -http -nocolored $dummy $verbose";
		msgVerbose( $command );
		my $stdout = `$command`;
		my $rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );
	}
	if( $result ){
		print "$res";
		msgOut( "done" );
	} else {
		msgWarn( "no answer from the daemon" );
		msgErr( "NOT OK" );
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
	"bname=s"			=> \$opt_bname,
	"port=i"			=> \$opt_port,
	"http!"				=> \$opt_http )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found bname='$opt_bname'" );
msgVerbose( "found port='$opt_port'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# either the json or the basename or the port must be specified (and not both)
my $count = 0;
$count += 1 if $opt_json;
$count += 1 if $opt_bname;
$count += 1 if $opt_port != -1;
if( $count == 0 ){
	msgErr( "one of '--json' or '--bname' or '--port' options must be specified, none found" );
} elsif( $count > 1 ){
	msgErr( "one of '--json' or '--bname' or '--port' options must be specified, several were found" );
}
#if a bname is specified, build the full filename
if( $opt_bname ){
	$opt_json = File::Spec->catdir( Mods::Path::daemonsConfigurationsDir(), $opt_bname );
}
#if a json is specified, must have a listeningPort
if( $opt_json ){
	my $daemonConfig = Mods::Daemon::getConfigByPath( $opt_json );
	# must have a listening port
	msgErr( "daemon configuration must define a 'listeningPort' value, not found" ) if !$daemonConfig->{listeningPort};
}

if( !ttpErrs()){
	doStatus();
}

ttpExit();
