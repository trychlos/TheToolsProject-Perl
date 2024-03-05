# Copyright (@) 2023-2024 PWI Consulting
#
# OVH API Access

package Mods::Ovh;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::OvhApi;
use Mods::Path;
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# (I):
# (O):
# - an opaque handle on the OVH API connection
sub connect {

	my $credentials = File::Spec->catdir( Mods::Path::siteConfigurationsDir(), "ovh.ini" );

	my $api = Mods::OvhApi->new(
		timeout => 10,
		credentials => $credentials
	);

	#my $identity = $api->get( path => "/me" );
	#if( !$identity ){
	#	printf("Failed to retrieve identity: %s\n", $identity);
	#	return 0;
	#}
	#$identity = $identity->content();
	#printf("Welcome %s\n", $identity->{'firstname'});
	
	return $api;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# (O):
# - a ref to the answer content, or undef
sub getByPath {
	my ( $api, $path ) = @_;
	my $res = undef;

	my $answer = $api->get( path => $path );
	if( $answer ){
		$res = $answer->content();
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# returns the list of subscribed services
# Makes use of '/service' API: as of 2024-03-05, '/services' API is in beta mode and returns some garbage
# (I):
# - the api opaque handle as returned from connect()
# (O):
# - a ref to a hash which contains subscribed services
sub getServices {
	my ( $api ) = @_;
	my $res = undef;

	my $url = '/service';
	my $list = getByPath( $api, $url );
	if( scalar @{$list} ){
		$res = {};
		foreach my $it ( @{$list} ){
			$res->{$it} = getByPath( $api, "$url/$it" );
		}
	}

	return $res;
}

1;
