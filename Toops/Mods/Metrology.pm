# Copyright (@) 2023-2024 PWI Consulting
#
# Metrology

package Mods::Metrology;

use strict;
use warnings;

use Data::Dumper;
use Sys::Hostname qw( hostname );

use Mods::Constants qw( :all );
use Mods::Toops;

# -------------------------------------------------------------------------------------------------
sub _hostname {
	return uc hostname;
}

# -------------------------------------------------------------------------------------------------
# get the lines of a result set, returns the interpreted hash
# first line gives column names
# second line gives column width
# third line and others give data
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
# (E):
# - topic string
# - result set
# (R):
# returns the count of published messages
sub publish {
	my ( $root, $set ) = @_;
	my $host = uc hostname;
	my $count = 0;
	foreach my $it ( @{$set} ){
		foreach my $key ( keys %{$it} ){
			my $command = "mqtt.pl publish -topic $host/metrology/$root/$key -message \"$it->{$key}\"";
			Mods::Toops::msgOut( "  $command" );
			`$command`;
			$count += 1;
		}
	}
	return $count;
}

1;
