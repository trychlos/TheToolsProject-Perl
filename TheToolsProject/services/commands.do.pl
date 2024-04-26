# @(#) execute the specified commands for a service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --host=<name>           search for the service in the given host [${host}]
# @(-) --key=<name[,...]>      the key to be searched for in JSON configuration file, may be specified several times or as a comma-separated list [${key}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use TTP::Service;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	host => TTP::host(),
	key => ''
};

my $opt_service = $defaults->{service};
my $opt_host = $defaults->{host};
my $opt_keys = [];

# -------------------------------------------------------------------------------------------------
# execute the commands registered for the service
# manage macros:
# - HOST
# - SERVICE
sub executeCommands {
	msgOut( "executing '$opt_service [".join( ',', @{$opt_keys} )."]' commands from '$opt_host' host..." );
	my $cmdCount = 0;
	my $host = $opt_host || TTP::host();
	my $hostConfig = TTP::getHostConfig( $host );
	my $serviceConfig = TTP::Service::serviceConfig( $hostConfig, $opt_service );
	if( $serviceConfig ){
		my $hash = TTP::var( $opt_keys, { config => $serviceConfig });
		if( $hash && ref( $hash ) eq 'HASH' ){
			my $commands = $hash->{commands};
			if( $commands && ref( $commands ) eq 'ARRAY' && scalar @{$commands} > 0 ){
				foreach my $cmd ( @{$commands} ){
					$cmdCount += 1;
					$cmd =~ s/<HOST>/$host/g;
					$cmd =~ s/<SERVICE>/$opt_service/g;
					if( $running->dummy() ){
						msgDummy( $cmd );
					} else {
						msgOut( "+ $cmd" );
						my $stdout = `$cmd`;
						my $rc = $?;
						msgLog( "stdout='$stdout'" );
						msgLog( "got rc=$rc" );
					}
				}
			} else {
				msgWarn( "serviceConfig->[".join( ',', @{$opt_keys} )."] is not defined, or not an array, or is empty" );
			}
		} else {
			msgWarn( "serviceConfig->[".join( ',', @{$opt_keys} )."] is not defined (or not a hash)" );
		}
	} else {
		msgErr( "unable to find '$opt_service' service configuration on '$opt_host'" );
	}
	msgOut( "$cmdCount executed command(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"service=s"			=> \$opt_service,
	"host=s"			=> \$opt_host,
	"key=s@"			=> \$opt_keys )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found host='$opt_host'" );
msgVerbose( "found keys='".join( ',', @{$opt_keys} )."'" );

msgErr( "'--service' service name is required, but not found" ) if !$opt_service;
msgErr( "'--host' host name is required, but not found" ) if !$opt_host;
msgErr( "at least a key is required, but none found" ) if !scalar( @{$opt_keys} );

if( !TTP::errs()){
	executeCommands() if $opt_service && scalar( @{$opt_keys} );
}

TTP::exit();
