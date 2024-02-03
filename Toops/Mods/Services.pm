# Copyright (@) 2023-2024 PWI Consulting
#
# Manage services: an indirection level wanted to banalize instances and other resources between environments.
# E.g. given WS22-DEV-1.json and WS22-PROD-1.json configuration files, we are able to write, test and DEPLOY common scripts without any modification.
# In other words, the code must be the same. Inly implementation details vary, all these details being in json configuration.

package Mods::Services;

use strict;
use warnings;

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Toops;

# -------------------------------------------------------------------------------------------------
# check that the provided service name is valid on this machine
# if found and valid, set it in the current command data
# (E):
# - candidate service name
# - options, which can be:
#   > mandatory: true|false, defaulting to true
# (S):
# returns the found and checked service object, or undef in case of an error
# if found, set up service -> { name, data } in TTPVars
sub checkServiceOpt {
	my ( $name, $opts ) = @_;
	$opts //= {};
	Mods::Toops::msgVerbose( "checkServiceOpt() entering with name='".( $name || '(undef)' )."'" );
	my $service = undef;
	if( $name ){
		my $config = Mods::Toops::getHostConfig();
		if( $config->{Services} ){
			if( exists( $config->{Services}{$name} )){
				Mods::Toops::msgVerbose( "found service='$name'" );
				$service = $name;
				my $TTPVars = Mods::Toops::TTPVars();
				$TTPVars->{$TTPVars->{run}{command}{name}}{service} = {
					name => $service,
					data => $config->{Services}{$name}
				};
				#print Dumper( $TTPVars->{$TTPVars->{run}{command}{name}} );
			} else {
				Mods::Toops::msgErr( "service '$name' is not defined in host configuration" );
			}
		} else {
			Mods::Toops::msgErr( "no 'Services' defined in host configuration" );
		}
	} else {
		my $mandatory = true;
		$mandatory = $opts->{mandatory} if exists $opts->{mandatory};
		if( $mandatory ){
			Mods::Toops::msgErr( "'--service' option is mandatory, but none as been found" );
		} else {
			Mods::Toops::msgVerbose( "'--service' option is optional, has not been specified" );
		}
	}
	Mods::Toops::msgVerbose( "checkServiceOpt() returning with service='".( $service || '(undef)' )."'" );
	return $service;
}

# -------------------------------------------------------------------------------------------------
# returns the (sorted) list if defined DBMS instance's names
# (E):
# - host configuration
# (S):
# - an ascii-sorted [0-9A-Za-z] array of strings
sub getDefinedDBMSInstances {
	my ( $config ) = @_;
	my @list = keys %{$config->{DBMSInstances}};
	return sort @list;
}

# -------------------------------------------------------------------------------------------------
# returns the sorted list of defined service's names
# (E):
# - host configuration
# - optional options hash with the following keys:
#   > hidden: whether to also return hidden services, defaulting to false
# (S):
# - an ascii-sorted [0-9A-Za-z] array of strings
sub getDefinedServices {
	my ( $config, $opts ) = @_;
	$opts //= {};
	my $returnHiddens = false;
	$returnHiddens = $opts->{hidden} if exists $opts->{hidden};
	my @list = ();
	foreach my $service ( keys %{$config->{Services}} ){
		my $hidden = false;
		$hidden = $config->{Services}{$service}{hidden} if exists $config->{Services}{$service}{hidden};
		if( !$hidden || $returnHiddens ){
			push( @list, $service );
		}
	}
	return sort @list;
}

# -------------------------------------------------------------------------------------------------
# returns the worktasks defined for the specified workload in the order of the service names
# (E):
# - host configuration
# - wanted workload name
# (S):
# - an array of task objects in the order of the service name
sub getDefinedWorktasks {
	my ( $config, $workload ) = @_;
	my @services = sort keys %{$config->{Services}};
	my @list = ();
	foreach my $service ( @services ){
		if( exists( $config->{Services}{$service}{workloads}{$workload} )){
			@list = ( @list, @{$config->{Services}{$service}{workloads}{$workload}} );
		}
	}
	return @list;
}

# -------------------------------------------------------------------------------------------------
# returns the used workloads, i.e. the workloads to which at least one item is candidate to.
# (E):
# - host configuration
# - optional options hash with the following keys:
#   > hidden: whether to also scan for hidden services, defaulting to false
# (S):
# - an ascii-sorted [0-9A-Za-z] array of strings
sub getUsedWorkloads {
	my ( $config, $opts ) = @_;
	my @services = Mods::Services::getDefinedServices( $config, $opts );
	my $list = {};
	foreach my $service ( @services ){
		if( exists( $config->{Services}{$service}{workloads} )){
			foreach my $workload ( keys %{$config->{Services}{$service}{workloads}} ){
				$list->{$workload} = 1;
			}
		}
	}
	my @names = keys %{$list};
	return sort @names;
}

=pod
# -------------------------------------------------------------------------------------------------
# returns the used workloads, i.e. the workloads to which at least one item is candidate to.
# (E):
# - host configuration
# - optional options hash with the following keys:
#   > hidden: whether to also return hidden services, defaulting to false
# (S):
# - a hash where:
#   > keys are the workload names
#   > values are an array of the found definitions hashes
sub getUsedWorkloads_old {
	my ( $config, $opts ) = @_;
	my @services = Mods::Services::getDefinedServices( $config, $opts );
	my $list = {};
	foreach my $service ( @services ){
		my $res = Mods::Toops::searchRecHash( $config->{Services}{$service}, 'workloads' );
		foreach my $it ( @{$res->{result}} ){
			foreach my $key ( keys %{$it->{data}} ){
				$list->{$key} = [] if !exists $list->{$key};
				my @foo = ( @{$list->{$key}}, @{$it->{data}{$key}} );
				$list->{$key} = \@foo;
			}
		}
	}
	return $list;
}
=cut

1;
