# @(#) test the status of the databases of the service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        service name [${service}]
# @(-) --[no]state             get state [${state}]
# @(-) --[no]mqtt              send status as a MQTT payload [${mqtt}]
# @(-) --[no]http              send status as a HTTP telemetry [${http}]
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

use Scalar::Util qw( looks_like_number );
use URI::Escape;

use TTP::Dbms;
use TTP::Service;
use TTP::Telemetry;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	state => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_service = $defaults->{service};
my $opt_state = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# get the state of all databases of the specified service
# Also publish as a labelled telemetry the list of possible values
# (same behavior than for example Prometheus windows_explorer which display the status of services)
# We so publish:
# - on MQTT, two payloads as .../state and .../state_desc
# - to HTTP, 10 numerical payloads, only one having a one value
sub doState {
	msgOut( "get database(s) state for '$opt_service'..." );
	my $hostConfig = TTP::getHostConfig();
	my $serviceConfig = TTP::Service::serviceConfig( $hostConfig, $opt_service );
	my $instance = undef;
	my @databases = undef;
	if( $serviceConfig ){
		$instance = TTP::Dbms::checkInstanceName( undef, { serviceConfig => $serviceConfig });
		msgVerbose( "found instance='".( $instance || 'undef' )."'" );
		if( $instance ){
			@databases = @{$serviceConfig->{DBMS}{databases}} if exists $serviceConfig->{DBMS}{databases};
			msgVerbose( "found databases='".( scalar @databases ? join( ',', @databases ) : 'none' )."'" );
		} else {
			msgErr( "unable to find a suitable DBMS instance for '$opt_service' service" );
		}
	} else {
		msgErr( "unable to find '$opt_service' service configuration for '$hostConfig->{name}' host" );
	}
	if( $instance && scalar @databases ){
		my $list = [];
		my $code = 0;
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		foreach my $db ( @databases ){
			msgOut( "  database '$db'" );
			my $result = TTP::Dbms::hashFromTabular( ttpFilter( `dbms.pl sql -instance $instance -command \"select state, state_desc from sys.databases where name='$db';\" -tabular -nocolored $dummy $verbose` ));
			my $row = @{$result}[0];
			# due to the differences between the two publications contents, publish separately
			# -> stdout
			foreach my $key ( sort keys %{$row} ){
				print "  $key: $row->{$key}".EOL;
			}
			if( $opt_mqtt ){
				# -> MQTT: only publish the label as state=<label>
				print `telemetry.pl publish -metric state -value $row->{state_desc} -label instance=$instance -label database=$db -mqtt -nohttp -nocolored $dummy $verbose`;
				my $rc = $?;
				msgVerbose( "doState() MQTT key='$key' got rc=$rc" );
			}
			if( $opt_http ){
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
			# contrarily to what is said in the doc, seems that push gateway requires the TYPE line
				foreach my $key ( keys( %{$states} )){
					my $value = 0;
					$value = 1 if "$key" eq "$row->{state}";
					print `telemetry.pl publish -metric ttp_dbms_database_state -value $value -label instance=$instance -label database=$db -label state=$states->{$key} -nomqtt -http -nocolored $dummy $verbose`;
					my $rc = $?;	
					msgVerbose( "doState() HTTP key='$key' state='$states->{$key}' got rc=$rc" );
					$code += $rc;
				}
			}
		}
		if( $code ){
			msgErr( "NOT OK" );
		} else {
			msgOut( "done" );
		}
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
	"service=s"			=> \$opt_service,
	"state!"			=> \$opt_state,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http )){

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
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found state='".( $opt_state ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# must have a service
msgErr( "a service is required, not specified" ) if !$opt_service;

# if no option is given, have a warning message
msgWarn( "no status has been requested, exiting gracefully" ) if !$opt_state;

if( !TTP::errs()){
	doState() if $opt_state;
}

TTP::exit();
