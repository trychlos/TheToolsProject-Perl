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
# enumerate the services names 
# - in ascii-sorted order [0-9A-Za-z]
# - considering the 'hidden' option
# - and call the provided sub for each found
# (E):
# - host configuration
# - reference to a sub to be called on each enumerated service with:
#   > the service name
#   > the full service definition
#   > the options object
# - optional options hash with the following keys:
#   > hidden: whether to also return hidden services, defaulting to false
# (S):
# - a count of enumerated services
sub enumerateServices {
	my ( $config, $callback, $opts ) = @_;
	$opts //= {};
	my $useHiddens = false;
	$useHiddens = $opts->{hidden} if exists $opts->{hidden};
	my @list = sort keys %{$config->{Services}};
	my $count = 0;
	foreach my $service ( @list ){
		my $isHidden = false;
		$isHidden = $config->{Services}{$service}{hidden} if exists $config->{Services}{$service}{hidden};
		if( !$isHidden || $useHiddens ){
			$callback->( $service, $config->{Services}{$service}, $opts );
			$count += 1;
		}
	}
	return $count;
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
	$opts->{definedServices} = [];
	enumerateServices( $config, \&_getDefinedServices_cb, $opts );
	return @{$opts->{definedServices}};
}

sub _getDefinedServices_cb {
	my ( $service, $definition, $opts ) = @_;
	push( @{$opts->{definedServices}}, $service );
}

# -------------------------------------------------------------------------------------------------
# returns the worktasks defined for the specified workload in the order:
#  - specified by "order" key of the work task 
#  - defaulting to the service names
# (E):
# - host configuration
# - wanted workload name
# - optional options hash with the following keys:
#   > hidden: whether to also scan for hidden services, defaulting to false
# (S):
# - an array of task objects in the above canonical order
sub getDefinedWorktasks {
	my ( $config, $workload, $opts ) = @_;
	$opts //= {};
	my $displayHiddens = false;
	$displayHiddens = $opts->{hidden} if exists $opts->{hidden};
	my @services = sort keys %{$config->{Services}};
	# build here the to be sorted array and a hash which will be used to build the result
	my @list = ();
	foreach my $service ( @services ){
		my $isHidden = false;
		$isHidden = $config->{Services}{$service}{hidden} if exists $config->{Services}{$service}{hidden};
		if( !$isHidden || $displayHiddens ){
			if( exists( $config->{Services}{$service}{workloads}{$workload} )){
				my @tasks = @{$config->{Services}{$service}{workloads}{$workload}};
				foreach my $t ( @tasks ){
					$t->{service} = $service;
				}
				@list = ( @list, @tasks );
			}
		}
	}
	return sort { _taskOrder( $a ) cmp _taskOrder( $b ) } @list;
}

# sort tasks in their specified order, defaulting to the 'added' service name
sub _taskOrder {
	my( $it ) = @_;
	return exists $it->{order} ? $it->{order} : $it->{service};
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

1;
