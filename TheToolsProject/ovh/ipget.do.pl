# @(#) display the OVH server to which the IP service is attached
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<service>     the relevant applicative service [${service}]
# @(-) --ip=<name>             the IP OVH service name [${ip}]
# @(-) --[no]routed            display the currently routed server [${routed}]
# @(-) --[no]address           display the address block of the IP service [${address}]
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

use TTP::Ovh;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
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
	msgOut( "display server to which '".( $opt_service || $opt_ip )."' FO IP is attached..." );
	my $res = false;

	if( $opt_service ){
		my $serviceConfig = $TTPVars->{$ttp->{run}{command}{name}}{service};
		if( $serviceConfig->{data}{ovh} ){
			if( $serviceConfig->{data}{ovh}{ip} ){
				$opt_ip = $serviceConfig->{data}{ovh}{ip};
				msgVerbose( "got IP service name '$opt_ip'" );
			} else {
				msgErr( "the '$opt_service' service doesn't have any 'ovh.ip' configuration" );
			}
		} else {
			msgErr( "the '$opt_service' service doesn't have any 'ovh' configuration" );
		}
	}
	if( $opt_ip ){
		my $api = TTP::Ovh::connect();
		if( $api ){
			my $result = TTP::Ovh::getContentByPath( $api, "/ip/service/$opt_ip" );
			print "  routedTo: $result->{routedTo}{serviceName}".EOL if $opt_routed;
			print "  address: $result->{ip}".EOL if $opt_address;
			$res = true;
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"service=s"			=> \$opt_service,
	"ip=s"				=> \$opt_ip,
	"routed!"			=> \$opt_routed,
	"address!"			=> \$opt_address )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found ip='$opt_ip'" );
msgVerbose( "found routed='".( $opt_routed ? 'true':'false' )."'" );
msgVerbose( "found address='".( $opt_address ? 'true':'false' )."'" );

# either the IP OVH service name is provided, or it can be found as part of an applicative service definition
if( $opt_service ){
	if( $opt_ip ){
		msgErr( "only one of '--service' or '--ip' must be specified, both found" );
	} else {
		TTP::Service::checkServiceOpt( $opt_service );
	}
} elsif( !$opt_ip ){
	msgErr( "either '--service' or '--ip' must be specified, none found" );
}

# at least one of -routed or -address must be asked
my $count = 0;
$count += 1 if $opt_routed;
$count += 1 if $opt_address;
msgErr( "either '--routed' or '--address' option must be specified" ) if !$count;

if( !TTP::errs()){
	doGetIP();
}

TTP::exit();
