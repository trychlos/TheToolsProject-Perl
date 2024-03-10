# Copyright (@) 2023-2024 PWI Consulting
#
# Credentials

package Mods::Credentials;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Path;
use Mods::Toops;

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
		$res = Mods::Toops::var( $keys );
		# if not found, looks at credentials/toops.json
		if( !defined( $res )){
			my $fname = File::Spec->catdir( Mods::Path::credentialsDir(), "toops.json" );
			my $data = Mods::Toops::evaluate( Mods::Toops::jsonRead( $fname ));
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
			my $host = Mods::Toops::_hostname();
			my $fname = File::Spec->catdir( Mods::Path::credentialsDir(), "$host.json" );
			my $data = Mods::Toops::evaluate( Mods::Toops::jsonRead( $fname ));
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
