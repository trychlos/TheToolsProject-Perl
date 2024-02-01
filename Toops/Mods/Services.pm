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
	my $config = Mods::Toops::getHostConfig();
	my @list = keys %{$config->{Services}};
	return @list;
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
	Mods::Toops::msgOut( "displaying defined services..." );
	my @list = Mods::Services::getDefinedServices();
	my @sorted = sort @list;
	foreach my $it ( @sorted ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @sorted." found defined service(s)" );
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

1;
