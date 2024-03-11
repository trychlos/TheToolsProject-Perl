# Copyright (@) 2023-2024 PWI Consulting
#
# Telemetry

package Mods::Telemetry;

use strict;
use warnings;

use Data::Dumper;
use HTTP::Request::Common;
use LWP::UserAgent;
use URI::Escape;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Toops;

# -------------------------------------------------------------------------------------------------
# publish the provided results sets to HTTP gateway
# the URL path is automatically built with /host/<HOST>/labelname1/labelvalue1/.../metric
# (I):
# - metric name
# - metric value
# - array ref of 'name=value' labels
# - an optional options hash with following keys:
#   > httpPrefix: a prefix to be set on the metric
#   > httpOptions: an array ref which may contain pairs of 'name=value' to be interpreted here
#     - type=yes|no: whether to publish a type comment line before the value, defaulting to true
# (O):
# returns the count of published messages (should be one)
sub httpPublish {
	my ( $metric, $value, $labels, $opts ) = @_;
	$opts //= {};
	my $count = 0;
	my $url = Mods::Toops::var([ 'Telemetry', 'withHttp', 'url' ]);
	if( $url ){
		foreach my $it ( @{$labels} ){
			my @words = split( /=/, $it );
			$url .= "/$words[0]/$words[1]";
		}
		# get metric prefix
		my $prefix = "";
		$prefix = $opts->{httpPrefix} if $opts->{httpPrefix};
		# interpret passed-in http options
		my $optionstr = [];
		$optionstr = $opts->{httpOptions} if exists $opts->{httpOptions};
		my $options = {};
		foreach my $it ( @{$optionstr} ){
			my @words = split( /=/, $it, 2 );
			$options->{$words[0]} = $words[1];
		}
		# build the request
		my $ua = LWP::UserAgent->new();
		my $req = HTTP::Request->new( POST => $url );
		my $name = "$prefix$metric";
		$name =~ s/\./_/g;
		# content
		# contrarily to what is said in the doc, seems that push gateway requires the TYPE line
		my $withType = true;
		$withType = ( $options->{type} eq 'yes' ) if exists $options->{type} && ( $options->{type} eq 'yes' || $options->{type} eq 'no' );
		my $str = $withType ? "# TYPE $name gauge\n" : "";
		my $qualifier = "";
		$qualifier = uri_unescape( $options->{label} ) if exists $options->{label};
		$str .= "$name$qualifier $value\n";
		msgVerbose( "Telemetry::Publish() url='$url' content='$str'" );
		$req->content( $str );
		my $response = $ua->request( $req );
		msgVerbose( Dumper( $response ));
		$count += 1 if $response->is_success;
		msgWarn( "Telemetry::httpPublish() Code: ".$response->code." MSG: ".$response->decoded_content ) if !$response->is_success;
	} else {
		msgWarn( "Telemetry::httpPublish() no HTTP URL available" );
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# publish the provided results sets to MQTT bus
# the topic is automatically built with <HOST>/telemetry/labelname1/labelvalue1/.../metric
# (I):
# - metric name
# - metric value
# - array ref of 'name=value' labels
# - an optional options hash with following keys:
#   > mqttPrefix: a prefix to be set on the metric (which happens to be the last part of the MQTT topic)
#   > mqttOptions: an array ref which may contain pairs of 'name=value' to be interpreted here
# (O):
# returns the count of published messages (should be one)
sub mqttPublish {
	my ( $metric, $value, $labels, $opts ) = @_;
	$opts //= {};
	my $count = 0;
	my $command = Mods::Toops::var([ 'Telemetry', 'withMqtt', 'command' ]);
	if( $command ){
		my $topic = Mods::Toops::ttpHost();
		$topic .= "/telemetry";
		foreach my $it ( @{$labels} ){
			my @words = split( /=/, $it );
			$topic .= "/$words[0]/$words[1]";
		}
		my $prefix = "";
		$prefix = $opts->{mqttPrefix} if $opts->{mqttPrefix};
		$topic .= "/$prefix$metric";
		$command =~ s/<SUBJECT>/$topic/;
		$command =~ s/<DATA>/$value/;
		$command =~ s/<OPTIONS>//;
		my $TTPVars = Mods::Toops::TTPVars();
		my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
		my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		my $rc = $?;
		msgVerbose( "Telemetry::mqttPublish() got rc=$rc" );
		$count += 1 if !$rc;
	} else {
		msgWarn( "Telemetry::mqttPublish() no MQTT command available" );
	}
	return $count;
}

1;
