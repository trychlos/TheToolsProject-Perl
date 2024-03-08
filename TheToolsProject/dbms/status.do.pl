# @(#) test the status of the databases of the service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        service name [${service}]
# @(-) --[no]state             get state [${state}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Scalar::Util qw( looks_like_number );
use URI::Escape;

use Mods::Constants qw( :all );
use Mods::Dbms;
use Mods::Message;
use Mods::Telemetry;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	state => 'no'
};

my $opt_service = $defaults->{service};
my $opt_state = false;

# -------------------------------------------------------------------------------------------------
# get the state of all databases of the specified service
# Also publish as a labelled telemetry the list of possible values
# (same behavior than for example Prometheus windows_explorer which display the status of services)
# We so publish:
# - on MQTT, two payloads as .../state and .../state_desc
# - to HTTP, 10 numerical payloads, only one having a one value
sub doState {
	Mods::Message::msgOut( "get database(s) state for '$opt_service'..." );
	my $hostConfig = Mods::Toops::getHostConfig();
	my $instance = $hostConfig->{Services}{$opt_service}{instance} if exists $hostConfig->{Services}{$opt_service}{instance};
	Mods::Message::msgVerbose( "found instance='$instance'" );
	my @databases = @{$hostConfig->{Services}{$opt_service}{databases}} if exists $hostConfig->{Services}{$opt_service}{databases};
	Mods::Message::msgVerbose( "found databases='".join( ', ', @databases )."'" );
	if( $instance && scalar @databases ){
		my $list = [];
		my $code = 0;
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		foreach my $db ( @databases ){
			Mods::Message::msgOut( "  database '$db'" );
			my $result = Mods::Dbms::hashFromTabular( Mods::Toops::ttpFilter( `dbms.pl sql -instance $instance -command \"select state, state_desc from sys.databases where name='$db';\" -tabular -nocolored $dummy $verbose` ));
			my $row = @{$result}[0];
			# due to the differences between the two publications contents, publish separately
			# -> MQTT
			foreach my $key ( keys %{$row} ){
				print `telemetry.pl publish -metric $key -value $row->{$key} -label instance=$instance -label database=$db -nocolored $dummy $verbose -nohttp`;
				my $rc = $?;
				Mods::Message::msgVerbose( "doState() MQTT key='$key' got rc=$rc" );
			}
			# -> HTTP
			# Source: https://learn.microsoft.com/fr-fr/sql/relational-databases/system-catalog-views/sys-databases-transact-sql?view=sql-server-ver16
			my $states = {
				'0' => 'online',
				'1' => 'restoring',
				'2' => 'recovering',
				'3' => 'recovery_pending',
				'4' => 'suspect',
				'5' => 'emergency',
				'6' => 'offline',
				'7' => 'copying',
				'10' => 'offline_secondary'
			};
			my $first = true;
			foreach my $key ( keys( %{$states} )){
				my $value = 0;
				$value = 1 if "$key" eq "$row->{state}";
				my $type = $first ? "" : "-httpOption type=no";
				# this option will be passed as a metric qualifier instead of being part of the url
				#my $label = "-httpOption label={state=".uri_escape( "\"$states->{$key}\"" )."}";
				#print `telemetry.pl publish -metric telemetry_dbms_state -value $value -label instance=$instance -label database=$db $label nocolored $dummy $verbose -nomqtt $type`;
				# this works the same, but using labels in the path instead of metric qualifier
				my $label = "-httpOption label={state=".uri_escape( "\"$states->{$key}\"" )."}";
				print `telemetry.pl publish -metric telemetry_dbms_database_state -value $value -label instance=$instance -label database=$db -label state=$states->{$key} -nocolored $dummy $verbose -nomqtt $type`;
				my $rc = $?;
				Mods::Message::msgVerbose( "doState() HTTP key='$key' got rc=$rc" );
				$code += $rc;
				#$first = false;
			}
		}
		if( $code ){
			Mods::Message::msgErr( "NOT OK" );
		} else {
			Mods::Message::msgOut( "done" );
		}
	} else {
		Mods::Message::msgWarn( "instance not found or no registered database" );
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
	"state!"			=> \$opt_state )){

		Mods::Message::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Message::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found service='$opt_service'" );
Mods::Message::msgVerbose( "found state='".( $opt_state ? 'true':'false' )."'" );

# must have a service
Mods::Message::msgErr( "a service is required, not specified" ) if !$opt_service;

# if no option is given, have a warning message
Mods::Message::msgWarn( "no status has been requested, exiting gracefully" ) if !$opt_state;

if( !Mods::Toops::errs()){
	doState() if $opt_state;
}

Mods::Toops::ttpExit();
