# @(#) display the machine which holds the live production of this service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        the named service [${service}]
# @(-) --environment=<type>    the searched for environment [${environment}]
#
# @(@) This script relies on the 'status/get_live' entry in the JSON configuration file.
# @(@) *All* machines are scanned until a 'status/get_live' command has been found for the service for the environment.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	environment => 'X'
};

my $opt_service = $defaults->{service};
my $opt_environment = $defaults->{environment};

# -------------------------------------------------------------------------------------------------
# A single response is expected (or none)
sub getLive {
	msgOut( "displaying live '$opt_environment' machine for '$opt_service' service..." );
	my @hosts = Mods::Toops::getDefinedHosts();
	msgVerbose( "found ".scalar @hosts." host(s)" );
	my $found = false;
	foreach my $host ( @hosts ){
		msgVerbose( "examining '$host'" );
		my $hostConfig = Mods::Toops::getHostConfig( $host );
		if( $hostConfig->{Environment}{type} eq $opt_environment && exists( $hostConfig->{Services}{$opt_service} )){
			msgVerbose( "  $hostConfig->{Environment}{type}: $host" );
			if( exists( $hostConfig->{Services}{$opt_service}{status}{get_live} )){
				my $command = $hostConfig->{Services}{$opt_service}{status}{get_live};
				if( $command ){
					$found = true;
					my $stdout = `$command`;
					my $rc = $?;
					msgVerbose( $stdout );
					msgVerbose( "rc=$rc" );
					if( !$rc ){
						my @output = grep( !/^\[|^\(ERR|^\(WAR|^\(VER|^\(DUM/, split( /[\r\n]/, $stdout ));
						if( scalar( @output )){
							# expects a single line
							my @words = split( /\s+/, $output[0] );
							print "  live: ".$words[scalar( @words )-1].EOL;
						}
					}
					last;
				}
			}
		}
	}
	if( $found ){
		msgOut( "done" );
	} else {
		msgErr( "no 'get_live' command found" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"service=s"			=> \$opt_service,
	"environment=s"		=> \$opt_environment )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found environment='$opt_environment'" );

msgErr( "'--service' service name must be specified, but is not found" ) if !$opt_service;
msgErr( "'--environment' environment type must be specified, but is not found" ) if !$opt_environment;

if( !ttpErrs()){
	getLive();
}

ttpExit();
