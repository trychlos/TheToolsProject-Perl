# @(#) manage Windows services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        apply to specified service [${service}]
# @(-) --[no]query             query the service state [${query}]
# @(-) --[no]mqtt              publish the result as a MQTT telemetry [${mqtt}]
# @(-) --[no]http              publish the result as a HTTP telemetry [${http}]
#
# @(@) Other options may be provided to this script after a '--' double dash, and will be passed to the 'telemetry.pl publish' verb.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	query => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_service = $defaults->{service};
my $opt_query = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# query the status of a service
sub doServiceQuery {
	msgOut( "querying the '$opt_service' service status..." );
	my $command = "sc query $opt_service | findstr STATE";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	my $res = ( $rc == 0 );
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	if( $res ){
		my @words = split( /\s+/, $stdout );
		my $label = $words[scalar( @words )-1];
		my $value = "$words[scalar( @words )-2]";
		msgOut( "  $value: $label" );
		if( $opt_mqtt || $opt_http ){
			my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
			my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
			if( $opt_mqtt ){
				msgOut( "publishing to MQTT" );
				$command = "telemetry.pl publish -metric state -value $label ".join( ' ', @ARGV )." -label role=$opt_service -mqtt -nohttp -nocolored $dummy $verbose";
				msgVerbose( $command );
				$stdout = `$command`;
				$rc = $?;
				msgVerbose( $stdout );
				msgVerbose( "rc=$rc" );
			}
			if( $opt_http ){
				msgOut( "publishing to HTTP" );
				# Source: https://learn.microsoft.com/en-us/windows/win32/services/service-status-transitions
				my $states = {
					'1' => 'stopped',
					'2' => 'start_pending',
					'3' => 'stop_pending',
					'4' => 'running',
					'5' => 'continue_pending',
					'6' => 'pause_pending',
					'7' => 'paused'
				};
				foreach my $key ( keys( %{$states} )){
					my $metric_value = ( $key eq $value ) ? "1" : "0";
					$command = "telemetry.pl publish -metric ttp_service_daemon -value $metric_value ".join( ' ', @ARGV )." -label role=$opt_service -label state=$states->{$key} -nomqtt -http -nocolored $dummy $verbose";
					msgVerbose( $command );
					$stdout = `$command`;
					$rc = $?;
					msgVerbose( $stdout );
					msgVerbose( "rc=$rc" );
				}
			}
		}
	} else {
		msgWarn( "most probably, the service doesn't exist" );;
	}
	if( $res ){
		msgOut( "success" );
	} else {
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
	"service=s"			=> \$opt_service,
	"query!"			=> \$opt_query,
	"mqtt!"				=> \$opt_mqtt,
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
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found query='".( $opt_query ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# a service name is mandatory when querying its status
msgErr( "a service name is mandatory when querying for a status" ) if $opt_query && !$opt_service;

if( !ttpErrs()){
	doServiceQuery() if $opt_service && $opt_query;
}

ttpExit();
