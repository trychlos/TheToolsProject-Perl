# Copyright (@) 2023-2024 PWI Consulting
#
# The machine configuration is a hash with the hostname as the single top key of this hash
# Values are:
# - DBMSInstances: a hash which describes the running DBMS instances on the machine

package Mods::HostConf;

use strict;
use warnings;

use Mods::Constants;
use Mods::Toops;

use File::Spec;
use JSON;
use Sub::Exporter;
use Sys::Hostname qw( hostname );

Sub::Exporter::setup_exporter({
	exports => [ qw(
		init
	)]
});

# -------------------------------------------------------------------------------------------------
# returns the machine configuration object
sub init {
	my $object = {};
	my $host = hostname;
	my $json_path = File::Spec->catdir( $ENV{TTP_SITE}, $host.'.json' );
	if( -f $json_path ){
		my $json_text = do {
		   open( my $json_fh, "<:encoding(UTF-8)", $json_path ) or die( "Can't open '$json_path': $!\n" );
		   local $/;
		   <$json_fh>
		};
		my $json = JSON->new;
		$object = $json->decode( $json_text );
		Mods::Toops::msgErr( "machine configuration '$json_path': '$host' key is missing" ) if !exists( $object->{$host} );
	} else {
		Mods::Toops::msgWarn( "machine configuration file '$json_path' not found or not readable" );
	}
	return $object;
}

1;
