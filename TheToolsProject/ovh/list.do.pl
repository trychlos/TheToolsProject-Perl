# @(#) list OVH services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]services          list subscribed services [${services}]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Ovh;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	services => 'no'
};

my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list all the subscribed services
sub listServices {
	Mods::Message::msgOut( "displaying subscribed services..." );
	my $api = Mods::Ovh::connect();
	if( $api ){
		# full identity
		#my $list = Mods::Ovh::get( $api, "/me" );
		#print "me".EOL.Dumper( $list );

		# three dedicated servers at that time
		#my $list = Mods::Ovh::get( $api, "/dedicated/server" );
		#print "dedicated/server".EOL.Dumper( $list );

		# all used ipv4+ipv6 addresses
		#my $list = Mods::Ovh::get( $api, "/ip" );
		#print "ip".EOL.Dumper( $list );

		# a list of services ids
		my $count = 0;
		my @missingDisplayName = ();
		my @routeUrl = ();
		my $services = Mods::Ovh::getServices( $api );
		foreach my $key ( keys %{$services} ){
			my $first = true;
			if( $services->{$key}{resource}{displayName} ){
				if( $first ){
					print "+ ";
					$first = false;
				} else {
					print "  ";
				}
				print "$key: resource.displayName: $services->{$key}{resource}{displayName}".EOL;
			} else {
				push( @missingDisplayName, $key );
			}
			if( $services->{$key}{route}{url} ){
				if( $first ){
					print "+ ";
					$first = false;
				} else {
					print "  ";
				}
				print "$key: route.url: $services->{$key}{route}{url}".EOL;
			} else {
				push( @missingRouteUrl, $key );
			}
			$count += 1;
		}
		Mods::Message::msgOut( "$count found subscribed service(s) (".scalar @missingDisplayName." missing display name(s), ".scalar @missingRouteUrl." missing route URL(s))" );
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
	"services!"			=> \$opt_services )){

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
Mods::Message::msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listServices() if $opt_services;
}

Mods::Toops::ttpExit();
