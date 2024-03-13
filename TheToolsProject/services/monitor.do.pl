# @(#) monitor the URLs of a service, publishing relevant telemetry
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run (ignored here) [${dummy}]
# @(-) --service=<name>            the service whose URLs are to be monitored [${service}]
# @(-) --[no]urls                  monitor URL's [${urls}]
# @(-) --[no]mqtt                  publish MQTT telemetry [${mqtt}]
# @(-) --[no]http                  publish HTTP telemetry [${http}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	urls => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_service = $defaults->{service};
my $opt_urls = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# request the urls defined for this service
sub doMonitorUrls {
	msgOut( "monitoring '$opt_service' URLs..." );

	# get the URLs to be monitored
	my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
	my $command = "services.pl vars -service $opt_service -key monitor,urls -nocolored $dummy $verbose";
	my @stdout = `$command`;
	my $rc = $?;
	msgLog( \@stdout );
	msgLog( "rc=$rc" );
	my $res = ( $rc == 0 );
	if( $res ){
		my $output = ttpFilter( @stdout );
		foreach my $it ( @{$output} ){
			my @words = split( /\s+/, $it );
			my $url = $words[1];
			msgOut( "found url='$url'" );
			
			# test each url
			$command = "http.pl get -url $url -header X-Sent-By -ignore";
			@stdout = `$command`;
			$rc = $?;
			msgLog( \@stdout );
			msgLog( "rc=$rc" );
			$output = ttpFilter( @stdout );
			@words = split( /\s+/, $output->[0] );
			my $live = $words[1];
			msgOut( "got live='$live'" );

			# and send the telemetry if opt-ed in
			my $live_label = "-label live=$live" if $live;
			my ( $proto, $path ) = split( /:\/\//, $url );
			my $status = ( $rc == 0 ) ? "1" : "0";
			my $proto_label = "-label proto=$proto";
			my $path_label = "-label path=$path";

			if( $opt_mqtt ){
				$command = "telemetry.pl publish -metric status -label service=$opt_service $live_label $proto_label $path_label -value=$status -mqttPrefix live/ -nohttp";
				@stdout = `$command`;
				msgLog( \@stdout );
			}
			if( $opt_http ){
				$command = "telemetry.pl publish -metric status -label service=$opt_service $live_label $proto_label $path_label -value=$status -httpPrefix ttp_live_ -nomqtt";
				@stdout = `$command`;
				msgLog( \@stdout );
			}
		}
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
	"urls!"				=> \$opt_urls,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http	)){

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
msgVerbose( "found urls='".( $opt_urls ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# service is mandatory
if( $opt_service ){
	Mods::Services::checkServiceOpt( $opt_service );
} else {
	msgErr( "service is required, but is not specified" );
}

# if '--url' is not specified then there is nothing to be monitored
msgWarn( "nothing to be monitored as '--urls' is falsy" ) if !$opt_urls;

if( !ttpErrs()){
	doMonitorUrls() if $opt_urls;
}

ttpExit();
