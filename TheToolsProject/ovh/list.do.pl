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

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Ovh;

my $TTPVars = TTP::TTPVars();

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
	msgOut( "displaying subscribed services..." );
	my $api = TTP::Ovh::connect();
	if( $api ){
		# full identity
		#my $list = TTP::Ovh::get( $api, "/me" );
		#print "me".EOL.Dumper( $list );

		# three dedicated servers at that time
		#my $list = TTP::Ovh::get( $api, "/dedicated/server" );
		#print "dedicated/server".EOL.Dumper( $list );

		# all used ipv4+ipv6 addresses
		#my $list = TTP::Ovh::get( $api, "/ip" );
		#print "ip".EOL.Dumper( $list );

		# a list of services ids
		my $count = 0;
		my @missingDisplayName = ();
		my @routeUrl = ();
		my $services = TTP::Ovh::getServices( $api );
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
		msgOut( "$count found subscribed service(s) (".scalar @missingDisplayName." missing display name(s), ".scalar @missingRouteUrl." missing route URL(s))" );
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
	"services!"			=> \$opt_services )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !TTP::errs()){
	listServices() if $opt_services;
}

TTP::exit();
