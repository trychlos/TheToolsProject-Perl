# Copyright (@) 2023-2024 PWI Consulting
#
# MQTT management.

package TTP::MQTT;

use strict;
use warnings;

use Data::Dumper;
use Net::MQTT::Simple;
use vars::global qw( $ttp );

use TTP;
use TTP::Constants qw( :all );
use TTP::Credentials;
use TTP::Message qw( :all );

$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

# ------------------------------------------------------------------------------------------------
# connect to the configured MQTT broker, keeping the connection alive (doesn't disconnect)
# (I):
# - a hash ref with following keys:
#   > broker: the full broker address, defaulting to global/host configured
#   > username: the connection username, defaulting to global/host configured
#   > password: the connection password, defaulting to global/host configured
#   > will: an optional last will, as a hash with following keys:
#     - topic, defaulting to empty
#     - payload, defaulting to empty
#     - retain, defaulting to false
# (O):
# - an opaque connection handle to be used when publishing (and disconnecting)
sub connect {
	my ( $args ) = @_;
	my $mqtt = undef;

	my $broker = $ttp->var([ 'MQTTGateway', 'broker' ]);
	$broker = $args->{broker} if $args->{broker};
	msgErr( "MQTT::connect() broker is not configured nor provided as an argument" ) if !$broker;

	my $username = TTP::Credentials::get([ 'MQTTGateway', 'username' ]);
	$username = $args->{username} if $args->{username};
	msgErr( "MQTT::connect() username is not configured nor provided as an argument" ) if !$username;

	my $password = TTP::Credentials::get([ 'MQTTGateway', 'password' ]);
	$password = $args->{password} if $args->{password};
	msgErr( "MQTT::connect() password is not configured nor provided as an argument" ) if !$password;

	$mqtt = Net::MQTT::Simple->new( $broker );
	if( $mqtt ){
		# define a last will if requested by the caller
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
		# login
		my $logged = $mqtt->login( $username, $password );
		msgVerbose( "MQTT::connect() logged-in with '$logged' account" );
	} else {
		msgErr( "MQTT::connect() unable to instanciate a new connection against '$broker' broker" );
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
		msgVerbose( "MQTT::disconnect()" );
		$handle->disconnect();
	} else {
		msgErr( "MQTT::disconnect() undefined connection handle" );
		TTP::stackTrace();
	}
}

1;
