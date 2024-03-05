# @(#) display the OVH server to which the IP service is attached
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<service>     the relevant applicative service [${service}]
# @(-) --ip=<name>             the IP OVH service name [${ip}]
# @(-) --[no]routed            display the currently routed server [${routed}]
# @(-) --[no]address           display the address block of the IP service [${address}]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Ovh;
use Mods::Services;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	ip => '',
	routed => 'no',
	address => 'no'
};

my $opt_service = $defaults->{service};
my $opt_ip = $defaults->{ip};
my $opt_routed = false;
my $opt_address = false;

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names
sub doGetIP {
	my $res = false;
	Mods::Message::msgOut( "display server to which '".( $opt_service || $opt_ip )."' FO IP is attached..." );

	if( $opt_service ){
		my $serviceConfig = $TTPVars->{$TTPVars->{run}{command}{name}}{service};
		if( $serviceConfig->{data}{ovh} ){
			if( $serviceConfig->{data}{ovh}{ip} ){
				$opt_ip = $serviceConfig->{data}{ovh}{ip};
				Mods::Message::msgVerbose( "got IP service name '$opt_ip'" );
			} else {
				Mods::Message::msgErr( "the '$opt_service' service doesn't have any 'ovh.ip' configuration" );
			}
		} else {
			Mods::Message::msgErr( "the '$opt_service' service doesn't have any 'ovh' configuration" );
		}
	}
	if( $opt_ip ){
		my $api = Mods::Ovh::connect();
		if( $api ){
			my $result = Mods::Ovh::getContentByPath( $api, "/ip/service/$opt_ip" );
			print "  routedTo: $result->{routedTo}{serviceName}".EOL if $opt_routed;
			print "  address: $result->{ip}".EOL if $opt_address;
			$res = true;
		}
	}
	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
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
	"ip=s"				=> \$opt_ip,
	"routed!"			=> \$opt_routed,
	"address!"			=> \$opt_address )){

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
Mods::Message::msgVerbose( "found ip='$opt_ip'" );
Mods::Message::msgVerbose( "found routed='".( $opt_routed ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found address='".( $opt_address ? 'true':'false' )."'" );

# either the IP OVH service name is provided, or it can be found as part of an applicative service definition
if( $opt_service ){
	if( $opt_ip ){
		Mods::Message::msgErr( "only one of '--service' or '--ip' must be specified, both found" );
	} else {
		Mods::Services::checkServiceOpt( $opt_service );
	}
} elsif( !$opt_ip ){
	Mods::Message::msgErr( "either '--service' or '--ip' must be specified, none found" );
}

# at least one of -routed or -address must be asked
my $count = 0;
$count += 1 if $opt_routed;
$count += 1 if $opt_address;
Mods::Message::msgErr( "either '--routed' or '--address' option must be specified" ) if !$count;

if( !Mods::Toops::errs()){
	doGetIP();
}

Mods::Toops::ttpExit();
