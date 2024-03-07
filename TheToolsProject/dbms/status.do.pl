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
sub doState {
	Mods::Message::msgOut( "get database(s) state for '$opt_service'..." );
	my $hostConfig = Mods::Toops::getHostConfig();
	my $instance = $hostConfig->{Services}{$opt_service}{instance} if exists $hostConfig->{Services}{$opt_service}{instance};
	Mods::Message::msgVerbose( "found instance='$instance'" );
	my @databases = @{$hostConfig->{Services}{$opt_service}{databases}} if exists $hostConfig->{Services}{$opt_service}{databases};
	Mods::Message::msgVerbose( "found databases='".join( ', ', @databases )."'" );
	if( $instance && scalar @databases ){
		my $list = [];
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		foreach my $db ( @databases ){
			Mods::Message::msgOut( "  database '$db'" );
			my $result = Mods::Dbms::hashFromTabular( Mods::Toops::ttpFilter( `dbms.pl sql -instance $instance -command \"select state, state_desc from sys.databases where name='$db';\" -tabular -nocolored $dummy $verbose` ));
			my $row = @{$result}[0];
			foreach my $key ( keys %{$row} ){
				my $http = looks_like_number( $row->{$key} ) ? "" : "-nohttp";
				print `telemetry.pl publish -metric $key -value $row->{$key} -label instance=$instance -label database=$db -httpPrefix telemetry_dbms_state_ -mqttPrefix state/ -nocolored $dummy $verbose $http`;
				my $rc = $?;
				Mods::Message::msgVerbose( "doState() key='$key' got rc=$rc" );
			}
		}
		Mods::Message::msgOut( "done" );
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
