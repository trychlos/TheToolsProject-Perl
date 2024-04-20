# @(#) display the machine which holds the live production of this service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        the named service [${service}]
# @(-) --environment=<type>    the searched for environment [${environment}]
# @(-) --[no]next              also search for next machine(s) [${next}]
# @(-) --[no]mqtt              publish MQTT telemetry [${mqtt}]
# @(-) --[no]http              publish HTTP telemetry [${http}]
#
# @(@) This script relies on the 'status/get_live' entry in the JSON configuration file.
# @(@) *All* machines are scanned until a 'status/get_live' command has been found for the service for the environment.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Services;

my $TTPVars = TTP::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	environment => 'X',
	next => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_service = $defaults->{service};
my $opt_environment = $defaults->{environment};
my $opt_next = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# Display the 'live' machine for a service
# If asked for, also display the next one
# and publish a telemetry if opted for
sub getLive {
	msgOut( "displaying live '$opt_environment' machine for '$opt_service' service..." );
	my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
	my @hosts = ();
	my $command = "services.pl list -service $opt_service -type $opt_environment -machines -nocolored $dummy $verbose";
	msgLog( $command );
	my $stdout = `$command`;
	my $rc = $?;
	msgLog( $stdout );
	msgLog( "rc=$rc" );
	my @output = grep( !/^\[|\(ERR|\(DUM|\(VER|\(WAR|^$/, split( /[\r\n]/, $stdout ));
	foreach my $it ( @output ){
		my @words = split( /\s+/, $it );
		push( @hosts, $words[scalar( @words )-1] );
	}
	# @hosts holds the list of hosts which say they host the service for the environment
	# we may find at most one live, and maybe several backups
	my $live = undef;
	my @nexts = ();
	foreach my $host ( @hosts ){
		msgVerbose( "examining '$host'" );
		my $hostConfig = TTP::Toops::getHostConfig( $host );
		if( exists( $hostConfig->{Services}{$opt_service}{status}{get_live} )){
			$command = $hostConfig->{Services}{$opt_service}{status}{get_live};
			if( $command ){
				$found = true;
				msgLog( $command );
				$stdout = `$command`;
				$rc = $?;
				msgVerbose( $stdout );
				msgVerbose( "rc=$rc" );
				if( !$rc ){
					my @output = grep( !/^\[|\(ERR|\(DUM|\(VER|\(WAR|^$/, split( /[\r\n]/, $stdout ));
					if( scalar( @output )){
						# expects a single line
						my @words = split( /\s+/, $output[0] );
						$live = $words[scalar( @words )-1];
						print "  live: $live".EOL;
					}
				} else {
					msgVerbose( "the service seems unable to identify its own live machine, saying there is none (maybe is it dead ?)" );
				}
				last;
			}
		}
	}
	if( $opt_next ){
		@nexts = $live ? grep( !/$live/, @hosts ) : @hosts;
		foreach my $next ( @nexts ){
			print "  next: $next".EOL;
		}
	}
	my $labels = "-label service=$opt_service -label environment=$opt_environment";
	my $next = join( ',', @nexts );
	if( $opt_mqtt ){
		# topic is HOST/telemetry/service/SERVICE/environment/ENVIRONMENT/machine/live=live
		# topic is HOST/telemetry/service/SERVICE/environment/ENVIRONMENT/machine/next=next
		my $mqtt_live = $live || 'none';
		$command = "telemetry.pl publish -metric live $labels -value=$mqtt_live -mqtt -mqttPrefix machine/ -nohttp";
		`$command`;
		if( $opt_next && scalar @nexts ){
			$command = "telemetry.pl publish -metric backup $labels -value=$next -mqtt -mqttPrefix machine/ -nohttp";
			`$command`;
		}
	}
	if( $opt_http ){
		# set the value "1" on the live metric when we have found one (i.e. is not undef)
		# we publish here one metric per host for the service and the environment with
		# - either a 'live' label if the host if the live host
		# - or a 'backup' label if the host is a backup host
		my $running = ttpHost();
		msgVerbose( "runningHost is '$running'" );
		foreach my $host ( @hosts ){
			my $value = ( $live && $live eq $host ) ? "1" : "0";
			my $httpLabels = $labels;
			my $http_live = $live || 'none';
			$httpLabels .= " -label live=$host" if $value eq "1";
			$httpLabels .= " -label backup=$host" if grep( /$host/, @nexts );
			$command = "telemetry.pl publish -metric ttp_service_machine $httpLabels -value=$value -nomqtt -http";
			`$command`;
		}
	}
	if( $found ){
		msgOut( "done" );
	} else {
		msgErr( "no 'get_live' command found" );
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
	"environment=s"		=> \$opt_environment,
	"next!"				=> \$opt_next,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::Toops::wantsHelp()){
	TTP::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found environment='$opt_environment'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

msgErr( "'--service' service name must be specified, but is not found" ) if !$opt_service;
msgErr( "'--environment' environment type must be specified, but is not found" ) if !$opt_environment;

if( !ttpErrs()){
	getLive();
}

ttpExit();
