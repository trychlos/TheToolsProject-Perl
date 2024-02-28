# Copyright (@) 2023-2024 PWI Consulting
#
# Metrology

package Mods::Metrology;

use strict;
use warnings;

use Data::Dumper;
use HTTP::Request::Common;
use LWP::UserAgent;
use Sys::Hostname qw( hostname );

use Mods::Constants qw( :all );
use Mods::Toops;

# -------------------------------------------------------------------------------------------------
sub _hostname {
	return uc hostname;
}

# -------------------------------------------------------------------------------------------------
# get the lines of a result set got from 'dbms.pl sql -tabular' output, returns the interpreted hash
# first line gives column names and column width
# second line and others give data
# may happen that column names include space; so only rely on columns width to split
sub interpretResultSet {
	my @set = @_;
	my @result = ();
	# compute the columns width
	my @w = split( /\s+/, $set[1] );
	my @width = ();
	foreach my $it ( @w ){
		push( @width, length( $it ));
	}
	# get the columns names (replacing spaces with _ if needed)
	my @columns = ();
	my $start = 0;
	for( my $col=0 ; $col<scalar @width ; ++$col ){
		my $str = substr( $set[0], $start, $width[$col] );
		$str =~ s/^\s+//;
		$str =~ s/\s+$//;
		$str =~ s/\s/_/g;
		push( @columns, $str );
		$start += 1 + $width[$col];
	}
	# and get the data
	for( my $ir=2 ; $ir<scalar @set ; ++$ir ){
		my $row = $set[$ir];
		next if !length( $row );
		my $res = {};
		$start = 0;
		for( my $col=0 ; $col<scalar @width ; ++$col ){
			my $data = substr( $row, $start, $width[$col] );
			$data =~ s/^\s*//;
			$data =~ s/\s*$//;
			$res->{$columns[$col]} = $data;
			$start += 1 + $width[$col];
		}
		push( @result, $res );
	}
	return \@result;
}

# -------------------------------------------------------------------------------------------------
# publish the provided results sets to MQTT bus
# (I):
# - topic string
# - result set as a hash ref
# - an optional options hash with following keys:
#   > maxCount: the maximum count of messages to be published (ignored if less than zero)
# (O):
# returns the count of published messages
sub mqttPublish {
	my ( $root, $set, $opts ) = @_;
	$opts //= {};
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{toops}{metrology}{withMqtt} )){
		Mods::Toops::msgVerbose( "Metrology::mqttPublish() TTPVars->{config}{toops}{metrology}{withMqtt}=$TTPVars->{config}{toops}{metrology}{withMqtt}" );
	} else {
		Mods::Toops::msgVerbose( "Metrology::mqttPublish() TTPVars->{config}{toops}{metrology}{withMqtt} is undef" );
	}
	my $count = 0;
	if( $TTPVars->{config}{toops}{metrology}{withMqtt} ){
		my $host = uc hostname;
		my $max = -1;
		$max = $opts->{maxCount} if exists( $opts->{maxCount} ) && $opts->{maxCount} >= 0;
		foreach my $key ( keys %{$set} ){
			last if $count >= $max && $max >= 0;
			my $command = "mqtt.pl publish -topic $host/metrology/$root/$key -payload \"$set->{$key}\"";
			Mods::Toops::msgVerbose( $command );
			`$command`;
			$count += 1;
		}
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# publish the provided results sets to Prometheus pushgateway
# (I):
# - topic string
# - result set
# - an optional options hash with following keys:
#   > prefix, a prefix to the metric name
# (O):
# returns the count of published messages
sub prometheusPublish {
	my ( $path, $set, $opts ) = @_;
	$opts //= {};
	my $TTPVars = Mods::Toops::TTPVars();
	if( exists( $TTPVars->{config}{toops}{metrology}{withPrometheus} )){
		Mods::Toops::msgVerbose( "Metrology::prometheusPublish() TTPVars->{config}{toops}{metrology}{withPrometheus}=$TTPVars->{config}{toops}{metrology}{withPrometheus}" );
	} else {
		Mods::Toops::msgVerbose( "Metrology::prometheusPublish() TTPVars->{config}{toops}{metrology}{withPrometheus} is undef" );
	}
	my $count = 0;
	my $prefix = "";
	$prefix = $opts->{prefix} if $opts->{prefix};
	if( $TTPVars->{config}{toops}{metrology}{withPrometheus} ){
		my $url = $TTPVars->{config}{toops}{prometheus}{url};
		$url .= "/job/metrology/host/".uc hostname;
		$url .= "/$path" if length $path;
		my $ua = LWP::UserAgent->new();
		my $req = HTTP::Request->new( POST => $url );
		foreach my $it ( @{$set} ){
			foreach my $key ( keys %{$it} ){
				my $metric = $prefix.$key;
				my $str = "# TYPE $metric gauge\n";
				$str .= "$metric $it->{$key}\n";
				Mods::Toops::msgVerbose( "Metrology::prometheusPublish() posting '$str' to url='$url'" );
				$req->content( $str );
				my $response = $ua->request( $req );
				#print Dumper( $response );
				Mods::Toops::msgVerbose( "Metrology::prometheusPublish() Code: ".$response->code." MSG: ".$response->decoded_content." Success: ".$response->is_success );
				$count += 1 if $response->is_success;
			}
		}
	}
	return $count;
}

# -------------------------------------------------------------------------------------------------
# publish the provided results sets to Prometheus push gateway
# (I):
# - path
# - comments as an array ref
# - metrics+values as a hash ref
# (O):
# - return true|false
sub prometheusPush {
	my ( $path, $comments, $values ) = @_;
	my $res = true;
	my $TTPVars = Mods::Toops::TTPVars();
	if( $TTPVars->{config}{toops}{prometheus}{url} ){
		my $url = $TTPVars->{config}{toops}{prometheus}{url};
		$url .= "$path" if length $path;
		my $ua = LWP::UserAgent->new();
		my $req = HTTP::Request->new( POST => $url );
		my $str = join( "\n", @{$comments} );
		my $fields = [];
		foreach my $key ( keys %{$values} ){
			push( @{$fields}, "$key $values->{$key}" );
		}
		$str .= "\n".join( "\n", @{$fields} )."\n";
		Mods::Toops::msgVerbose( "Metrology::prometheusPush() posting '$str' to url='$url'" );
		$req->content( $str );
		my $response = $ua->request( $req );
		$res = $response->is_success;
		#print Dumper( $response );
		Mods::Toops::msgVerbose( "Metrology::prometheusPush() Code: ".$response->code." MSG: ".$response->decoded_content." Success: ".$response->is_success );
	} else {
		Mods::Toops::msgVerbose( "calling Metrology::prometheusPush() while TTPVars->{config}{toops}{prometheus}{url} is undef" );
	}
	return $res;
}

1;
