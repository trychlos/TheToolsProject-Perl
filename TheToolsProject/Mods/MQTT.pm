# Copyright (@) 2023-2024 PWI Consulting
#
# MQTT management.

package Mods::MQTT;

use strict;
use warnings;

use Data::Dumper;
use Net::MQTT::Simple;

use Mods::Constants qw( :all );
use Mods::Toops;

$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

# ------------------------------------------------------------------------------------------------
# connect to the specified MQTT broker, keeping the connection alive (doesn't disconnect)
# (I):
# - broker
# - username
# - password
# - will: optional last will, as a hash with following keys:
#   > topic, defaulting to empty
#   > payload, defaulting to empty
#   > retain, defaulting to false
# (O):
# - an opaque connection handle to be used when disconnecting
sub connect {
	my ( $args ) = @_;
	my $mqtt = undef;

	Mods::Toops::msgErr( "no registered broker" ) if !$args->{broker};
	Mods::Toops::msgErr( "no registered username" ) if !$args->{username};
	Mods::Toops::msgErr( "no registered password" ) if !$args->{password};

	$mqtt = Net::MQTT::Simple->new( $args->{broker} );
	if( $mqtt ){
		if( $args->{will} ){
			my $topic = $args->{will}{topic} || '';
			my $payload = $args->{will}{payload} || '';
			my $retain = false;
			$retain = $args->{will}{retain} if exists $args->{will}{retain};
			$mqtt->last_will( $topic, $payload, $retain );
			$mqtt->{ttpLastWill} = {
				topic => $topic,
				payload => $payload,
				retain => $retain
			}
		}
		my $logged = $mqtt->login( $args->{username}, $args->{password} );
		Mods::Toops::msgVerbose( "MQTT::connect() logged-in with '$logged' account" );
	}
	
	return $mqtt;
}

# ------------------------------------------------------------------------------------------------
# disconnect from the specified MQTT broker
# (I):
# - opaque connection handle as returned from MQTT::connect()
sub disconnect {
	my ( $handle ) = @_;
	if( $handle ){
		if( $handle->{ttpLastWill} ){
			if( $handle->{ttpLastWill}{retain} ){
				$handle->retain( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			} else {
				$handle->publish( $handle->{ttpLastWill}{topic}, $handle->{ttpLastWill}{payload} );
			}
		}
		$handle->disconnect();
	} else {
		Mods::Toops::msgErr( "MQTT::disconnect() undefined connection handle" );
	}
}

1;
