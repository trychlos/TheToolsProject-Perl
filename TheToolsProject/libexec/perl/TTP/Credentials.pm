# Copyright (@) 2023-2024 PWI Consulting
#
# Credentials

package TTP::Credentials;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;
use TTP;

# ------------------------------------------------------------------------------------------------
# Returns the found credentials
# Note that we first search in toops/host configuration, and then in a dedicated credentials JSON file with the same key
# (I):
# - an array ref of the keys to be read
# (O):
# - the object found at the given address, or undef
sub get {
	my ( $keys ) = @_;
	my $res = undef;
	if( ref( $keys ) ne 'ARRAY' ){
		msgErr( "Credentials::get() expects an array, found '".ref( $keys )."'" );
	} else {
		# first look in the Toops/host configurations
		$res = $ttp->var( $keys );
		# if not found, looks at credentials/toops.json
		if( !defined( $res )){
			my $fname = File::Spec->catdir( TTP::Path::credentialsDir(), "toops.json" );
			my $data = TTP::evaluate( TTP::jsonRead( $fname ));
			$res = $data;
			foreach my $k ( @{$keys} ){
				if( exists( $res->{$k} )){
					$res = $res->{$k};
				} else {
					$res = undef;
					last;
				}
			}
		}
		# if not found, looks at credentials/<host>.json
		if( !defined( $res )){
			my $host = TTP::host();
			my $fname = File::Spec->catdir( TTP::Path::credentialsDir(), "$host.json" );
			my $data = TTP::evaluate( TTP::jsonRead( $fname ));
			$res = $data;
			foreach my $k ( @{$keys} ){
				if( exists( $res->{$k} )){
					$res = $res->{$k};
				} else {
					$res = undef;
					last;
				}
			}
		}
	}
	return $res;
}

1;
