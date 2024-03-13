#!/usr/bin/perl
# @(#) Switch a service to another host
#
# This script is run from an external (Linux) monitoring host.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Basename;
use File::Spec;
use Getopt::Long;

use Mods::Toops;
use Mods::Constants qw( :all );
use Mods::Message qw( :all );

# TTP initialization
my $TTPVars = Mods::Toops::initExtern();

my $me = basename( $0 );
my $nbopts = scalar @ARGV;
my $nberrs = 0;

my $defaults = {
	help => 'no',
	verbose => 'no',
	service => '',
	to => '',
	force => 'no'
};

my $opt_help = false;
my $opt_verbose = false;
my $opt_service = $defaults->{service};
my $opt_to = $defaults->{to};
my $opt_force = false;

# -------------------------------------------------------------------------------------------------
# 
sub msgHelp {
	print "Switch a service to another host
  Usage: $0 [options]
  where available options are:
    --[no]help              print this message, and exit [$defaults->{help}]
    --[no]verbose           verbosely run [$defaults->{verbose}]
    --service=<name>        the service to be switched [$defaults->{service}]
    --to=<name>             the machine to switch to [$defaults->{to}]
    --[no]force             check the initial conditions, but run even an error is detected [$defaults->{force}]
";
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$opt_help,
	"verbose!"			=> \$opt_verbose,
	"service=s"			=> \$opt_service,
	"to=s"				=> \$opt_to,
	"force!"			=> \$opt_force )){

		msgOut( "try '$0 --help' to get full usage syntax" );
		exit( 1 );
}

$opt_help = true if !$nbopts;

if( $opt_help ){
	msgHelp();
	exit( 0 );
}

msgVerbose( "found help='".( $opt_help ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $opt_verbose ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found to='$opt_to'" );
msgVerbose( "found force='".( $opt_force ? 'true':'false' )."'" );

msgErr( "'--service' option is mandatory but has not been found" ) if !$opt_service;
msgErr( "'--to' option is mandatory but has not been found" ) if !$opt_to;
exit( $nberrs ) if $nberrs;

# make sure the service is defined on the target host
# [services.pl list] displaying services defined on WS12DEV1...
#  Canal33
#  Dom.2008
# [services.pl list] 2 found defined service(s)
my $command = "ssh inlingua-user\@$opt_to services.pl list -services";
msgVerbose( $command );
my $stdout = `$command`;
my $rc = $?;
msgVerbose( $stdout );
msgVerbose( "rc=$rc" );
my @lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
my @check = grep( /$opt_service/, @lines );
if( !scalar( @check )){
	msgErr( "service '$opt_service' is not defined on '$opt_to' host" );
} else {
	msgOut( "service '$opt_service' exists" );
}
if( !$nberrs || $opt_force ){
	# get the list of hosts which hold the production of this service, and check that the target host is actually member of the group
	# [services.pl list] displaying machines which provide \'Canal33\' service in \'X\' environment...
	#    X: NS230134
	#    X: WS12PROD1
	# [services.pl list] 2 found machine(s)
	$command = "services.pl list -nocolored -service $opt_service -type X -machines";
	msgVerbose( $command );
	$stdout = `$command`;
	$rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	@lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
	my @hosts = ();
	foreach my $it ( @lines ){
		my @words = split( /\s+/, $it );
		push( @hosts, $words[2] );
		msgVerbose( "got $words[2]" );
	}
	@check = grep( /$opt_to/, @hosts );
	if( !scalar( @check )){
		msgErr( "to='$opt_to' is not a valid target among [".join( ', ', @hosts )."] production hosts" );
	} else {
		msgOut( "host '$opt_to' is a valid target" );
	}
}
if( !$nberrs || $opt_force ){
	# VERY IMPORTANT
	# first task is to stop the backup daemons on the target host
	msgOut( "stopping backup daemons..." );
	$command = "ssh inlingua-user\@$opt_to services.pl commands -service $opt_service -key monitor,switch";
	msgVerbose( $command );
	$stdout = `$command`;
	$rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );

	# second is to disable the backup scheduled tasks on the target host
	msgOut( "disabling backup scheduled tasks..." );
	$command = "ssh inlingua-adm\@$opt_to services.pl commands -service $opt_service -key monitor,admin";
	msgVerbose( $command );
	$stdout = `$command`;
	$rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );

	# and last switch the ip service itself
	# get the ip service
	msgOut( "switching the IP service..." );
	$command = "ssh inlingua-user\@$opt_to services.pl vars -service $opt_service -key monitor,ovh,ip";
	msgVerbose( $command );
	$stdout = `$command`;
	$rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	@lines = grep( !/^\[|\(WAR\)|^$/, split( /[\r\n]/, $stdout ));
	my $ipService = undef;
	if( scalar( @lines )){
		my @words = split( /\s+/, $lines[0] );
		$ipService = $words[2];
	}
	msgVerbose( "got ipService='$ipService'" );
	if( !$ipService ){
		msgWarn( "No IP service found for '$opt_service' service" );

	} else {
		# get the target host service
		$command = "ssh inlingua-user\@$opt_to ttp.pl vars -key Environment,physical,ovh";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );
		@lines = grep( !/^\[|\(WAR\)|^$/, split( /[\r\n]/, $stdout ));
		my $physical = undef;
		if( scalar( @lines )){
			my @words = split( /\s+/, $lines[0] );
			$physical = $words[2];
		}
		msgVerbose( "got physical='$physical'" );
		if( !$physical ){
			msgErr( "An OVH IP Failover is defined but no OVH server service has been found for '$opt_service' service" );
		} else {
			# get the url to be tested
			$command = "ssh inlingua-user\@$opt_to services.pl vars -service $opt_service -key monitor,url";
			msgVerbose( $command );
			$stdout = `$command`;
			$rc = $?;
			msgVerbose( $stdout );
			msgVerbose( "rc=$rc" );
			@lines = grep( !/^\[|\(WAR\)|^$/, split( /[\r\n]/, $stdout ));
			my $url = undef;
			if( scalar( @lines )){
				my @words = split( /\s+/, $lines[0] );
				$url = $words[2];
			}
			msgVerbose( "got url='$url'" );
			if( !$url ){
				msgWarn( "No URL is defined for '$opt_service' service" );
			}
			# running the switch requires ip service and target host, url is optional
			my $urlopt = $url ? "-url $url -sender $opt_to" : "";
			$urlopt = $url ? "-url $url -sender WS22DEV1" : "";
			$command = "ovh.pl ipswitch -ip $ipService -to $physical -wait $urlopt";
			msgVerbose( $command );
			$stdout = `$command`;
			$rc = $?;
			msgVerbose( $stdout );
			msgVerbose( "rc=$rc" );
		}
	}
	if( $nberrs ){
		msgErr( "NOT OK" );
	} else {
		msgOut( "success" );
	}
}

exit( $nberrs );
