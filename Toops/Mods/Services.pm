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
# returns the defined DBMS instances
sub getDefinedDBMSInstances {
	my $config = Mods::Toops::getHostConfig();
	my @list = keys %{$config->{DBMSInstances}};
	return @list;
}

# -------------------------------------------------------------------------------------------------
# returns the defined services
sub getDefinedServices {
	my ( $config ) = @_;
	my @list = keys %{$config->{Services}};
	return @list;
}

# -------------------------------------------------------------------------------------------------
# returns the used workloads, i.e. the workloads of which at least one item is candidate to
# we provide a hash where:
# - keys are the workload name's
# - values are an array of the found definitions
sub getUsedWorkloads {
	my ( $config ) = @_;
	my @services = Mods::Services::getDefinedServices( $config );
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

# -------------------------------------------------------------------------------------------------
# list the (sorted) defined DBMS instances
sub listDefinedDBMSInstances {
	my @list = Mods::Services::getDefinedDBMSInstances();
	my @sorted = sort @list;
	foreach my $it ( @sorted ){
		Mods::Toops::msgOut( PREFIX.$it );
	}
	Mods::Toops::msgOut( scalar @sorted." found defined DBMS instance(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the (sorted) defined services
sub listDefinedServices {
	my $config = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying services defined on $config->{host}..." );
	my @list = Mods::Services::getDefinedServices( $config );
	my @sorted = sort @list;
	foreach my $it ( @sorted ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @sorted." found defined service(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the (sorted) defined workloads
sub listUsedWorkloads {
	my $config = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workloads used on $config->{host}..." );
	my $list = Mods::Services::getUsedWorkloads( $config );
	my @names = keys %{$list};
	my @sorted = sort @names;
	foreach my $it ( @sorted ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @sorted." found used workload(s)" );
}

# -------------------------------------------------------------------------------------------------
# check that the provided service name is valid on this machine
# if found and valid, set it in the current command data
# (E):
# - candidate service name
# - options, which may have:
#   > mandatory: true|false, defaulting to true
# returns the found and checked service, or undef in case of an error
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
# list the tasks of the named workload
# this is an array of task items where the exact content actually depends of the task type.
# we so cannot really have a fun and always usable display
sub listWorkloadTasks {
	my ( $workload ) = @_;
	my $config = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workload tasks defined for $config->{host}\\$workload..." );
	my $list = Mods::Services::getUsedWorkloads( $config );
	foreach my $it ( @{$list->{$workload}} ){
		# if we have a name, make it the first line
		if( exists( $it->{name} )){
			print "+ $it->{name}".EOL;
		} else {
			print "+ (unnamed)".EOL;
		}
		# print other keys expecting values are all scalar
		foreach my $key ( keys %{$it} ){
			if( $key ne 'name' ){
				my $type = ref( $it->{$key} );
				if( !$type ){
					print "  $key: $it->{$key}".EOL;
				} elsif( $type eq 'ARRAY' ){
					print "  $key: ".join( ', ', @{$it->{$key}} ).EOL;
				} else {
					print "  $key: <object reference>".EOL;
				}
			}
		}
	}
	Mods::Toops::msgOut( scalar @{$list->{$workload}}." found defined task(s)" );
}

1;
