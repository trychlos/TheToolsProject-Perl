# Copyright (@) 2023-2024 PWI Consulting
#
# Manage services: an indirection level wanted to banalize instances and other resources between environments.
# E.g. given WS22DEV1.json and WS22PROD1.json configuration files, we are able to write, test and DEPLOY common scripts without any modification.
# In other words, the code must be the same. Only implementation details may vary, all these details being in json configurations.
#
# As of 2024-04-19, the service configuration can be written:
# - in a <service>.json configuration file
# - in a <hostname>.json configuration file, overriding the service-level items.
# Notes:
# - Service configuration file is optional, and may not exists for a service: the service may be entirely defined in hosts configuration files.
# - Even if the host doesn't want override any service key, it still MUST define the service in the "Services" object of its own configuration file.

package TTP::Services;

use strict;
use warnings;

use Data::Dumper;
use Hash::Merge qw( merge );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP;

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
	msgVerbose( "checkServiceOpt() entering with name='".( $name || '(undef)' )."'" );
	my $service = undef;
	if( $name ){
		my $config = TTP::getHostConfig();
		if( $config->{Services} ){
			if( exists( $config->{Services}{$name} )){
				msgVerbose( "found service='$name'" );
				$service = $name;
				my $TTPVars = TTP::TTPVars();
				$TTPVars->{$TTPVars->{run}{command}{name}}{service} = {
					name => $service,
					data => $config->{Services}{$name}
				};
				#print Dumper( $TTPVars->{$TTPVars->{run}{command}{name}} );
			} else {
				msgErr( "service '$name' is not defined in host configuration" );
			}
		} else {
			msgErr( "no 'Services' defined in host configuration" );
		}
	} else {
		my $mandatory = true;
		$mandatory = $opts->{mandatory} if exists $opts->{mandatory};
		if( $mandatory ){
			msgErr( "'--service' option is mandatory, but none as been found" );
		} else {
			msgVerbose( "'--service' option is optional, has not been specified" );
		}
	}
	msgVerbose( "checkServiceOpt() returning with service='".( $service || '(undef)' )."'" );
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
#   > the full service definition, i.e. the service level if it exists, maybe overriden by the host level
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
			$callback->( $service, serviceConfig( $config, $service ), $opts );
			$count += 1;
		}
	}
	return $count;
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
# (I):
# - host configuration
# - wanted workload name
# - optional options hash with the following keys:
#   > hidden: whether to also scan for hidden services, defaulting to false
# (O):
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
		my $serviceConfig = serviceConfig( $config, $service );
		my $isHidden = false;
		$isHidden = $serviceConfig->{hidden} if exists $serviceConfig->{hidden};
		if( !$isHidden || $displayHiddens ){
			if( exists( $serviceConfig->{workloads}{$workload} )){
				my @tasks = @{$serviceConfig->{workloads}{$workload}};
				foreach my $t ( @tasks ){
					$t->{service} = $service;
				}
				@list = ( @list, @tasks );
			}
		}
	}
	return sort { _taskOrder( $a ) cmp _taskOrder( $b ) } @list;
}

# sort tasks in their specified order, defaulting to the added service name
sub _taskOrder {
	my( $it ) = @_;
	return exists $it->{order} ? $it->{order} : $it->{service};
}

# -------------------------------------------------------------------------------------------------
# returns the used workloads, i.e. the workloads to which at least one service of the machine is candidate to.
# (I):
# - host configuration
# - optional options hash with the following keys:
#   > hidden: whether to also scan for hidden services, defaulting to false
# (O):
# - an ascii-sorted [0-9A-Za-z] array of strings
sub getUsedWorkloads {
	my ( $config, $opts ) = @_;
	$opts //= {};
	$opts->{usedWorkloads} = {};
	enumerateServices( $config, \&_getUsedWorkloads_cb, $opts );
	my @names = keys %{$opts->{usedWorkloads}};
	return sort @names;
}

sub _getUsedWorkloads_cb {
	my ( $service, $definition, $opts ) = @_;
	if( exists( $definition->{workloads} )){
		foreach my $workload ( keys %{$definition->{workloads}} ){
			$opts->{usedWorkloads}{$workload} = 1;
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Compute and return the full service configuration hash
# (I):
# - host configuration
# - service name
# (O):
# - a hash with full evaluated service configuration, or undef if the service is not defined in the host
sub serviceConfig {
	my ( $hostConfig, $serviceName ) = @_;
	my $result = undef;
	if( exists( $hostConfig->{Services}{$serviceName} )){
		my $serviceHash = TTP::jsonRead( TTP::Path::serviceConfigurationPath( $serviceName ), { ignoreIfNotExist => true });
		if( defined $serviceHash ){
			$serviceHash = serviceConfigMacrosRec( $serviceHash, { service => $serviceName });
			$serviceHash = TTP::hostConfigMacrosRec( $serviceHash, { host => $hostConfig->{name} });
			$serviceHash = TTP::evaluate( $serviceHash );
		}
		my $hostHash = serviceConfigMacrosRec( $hostConfig->{Services}{$serviceName}, { service => $serviceName });
		$result = merge( $hostHash, $serviceHash || {} );
		$result->{name} = $serviceName;
	}
	#print Dumper( $result );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Substitute the macros in a service configuration file
# (I):
# - the raw JSON hash
# - an options hash with following keys:
#   > service: the service name being treated
# (O):
# - the same with substituted macros:
#   > SERVICE
sub serviceConfigMacrosRec {
	my ( $hash, $opts ) = @_;
	my $ref = ref( $hash );
	if( $ref eq 'HASH' ){
		foreach my $key ( keys %{$hash} ){
			$hash->{$key} = serviceConfigMacrosRec( $hash->{$key}, $opts );
		}
	} elsif( $ref eq 'ARRAY' ){
		my @array = ();
		foreach my $it ( @{$hash} ){
			push( @array, serviceConfigMacrosRec( $it, $opts ));
		}
		$hash = \@array;
	} elsif( !$ref ){
		my $service = $opts->{service};
		$hash =~ s/<SERVICE>/$service/g;
	} else {
		msgVerbose( "Service::serviceConfigMacrosRec() unmanaged ref: '$ref'" );
	}
	return $hash;
}

1;
