# Copyright (@) 2023-2024 PWI Consulting
#
# OVH API Access

package TTP::Ovh;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::OvhApi;
use TTP::Path;
use TTP;

# ------------------------------------------------------------------------------------------------
# (I):
# (O):
# - an opaque handle on the OVH API connection
sub connect {

	my $credentials = File::Spec->catdir( TTP::Path::credentialsDir(), "ovh.ini" );
	msgVerbose( "Ovh::connect() credentials='$credentials'" );

	my $api = TTP::OvhApi->new(
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
# - an optional options hash with following keys:
#   > printAnswer, defaulting to false
# (O):
# - the request answer as a OvhAnswer instance
sub getAnswerByPath {
	my ( $api, $path, $opts ) = @_;
	$opts //= {};
	msgVerbose( "Ovh::getAnswerByPath() path='$path'" );

	my $answer = $api->get( path => $path );
	my $printAnswer = false;
	$printAnswer = $opts->{printAnswer} if exists $opts->{printAnswer};
	print Dumper( $answer ) if $printAnswer;

	msgVerbose( "Ovh::getAnswerByPath() status=".$answer->status()." isSuccess='".( $answer->isSuccess() ? 'true' : 'false' )."'");
	return $answer;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - an optional options hash with following keys:
#   > printAnswer, defaulting to false
# (O):
# - a ref to the answer content, or undef
sub getContentByPath {
	my ( $api, $path, $opts ) = @_;
	$opts //= {};
	my $res = undef;

	my $answer = getAnswerByPath( $api, $path, $opts );
	if( $answer->isSuccess()){
		$res = $answer->content();
	} else {
		msgLog( Dumper( $answer ));
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
	my $list = getContentByPath( $api, $url );
	if( scalar @{$list} ){
		$res = {};
		foreach my $it ( @{$list} ){
			$res->{$it} = getContentByPath( $api, "$url/$it" );
		}
	}

	return $res;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - the api opaque handle as returned from connect()
# - a path to request
# - the post parameters as a hash
# (O):
# - the request answer as a OvhAnswer instance
sub postByPath {
	my ( $api, $path, $params ) = @_;
	msgVerbose( "Ovh::postByPath() path='$path'" );

	my $answer = $api->post( path => $path, body => $params );
	print Dumper( $answer ) if $answer->isFailure();

	msgVerbose( "Ovh::postByPath() status=".$answer->status()." isSuccess='".( $answer->isSuccess() ? 'true' : 'false' )."'");
	return $answer;
}

1;