#!/usr/bin/perl
# @(#) Monitor the service URLs, alerting when not answered
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        the service to be monitored, may be specified several times or as a comma-separated list [${service}]
# @(-) --environment=<env>     the environment to be monitored [${environment}]
# @(-) --[no]alert             whether to alert on non-response [${alert}]
#
# @(@) This script is run from an external (Linux) monitoring host's crontab.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Basename;
use Getopt::Long;

use Mods::Toops;
use Mods::Constants qw( :all );
use Mods::Message qw( :all );

# TTP initialization
my $TTPVars = Mods::Toops::initExtern();

my $me = basename( $0 );
my $nbopts = scalar @ARGV;

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	environment => 'X',
	alert => 'no'
};

my $opt_service = $defaults->{service};
my $opt_environment = $defaults->{environment};
my $opt_alert = false;

# -------------------------------------------------------------------------------------------------
# 
sub doMonitor {
	msgOut( "monitoring '$opt_service' service URLs..." );
	# get the list of hosts which hold this environment production of this service
	# [services.pl list] displaying machines which provide \'Canal33\' service in \'X\' environment...
	#    X: NS230134
	#    X: WS12PROD1
	# [services.pl list] 2 found machine(s)
	my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
	my $command = "services.pl list -nocolored -service $opt_service -type $opt_environment -machines $dummy $verbose";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	#msgVerbose( join( "", @stdout ));
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	my @lines = grep( !/^\[|\(WAR|\(ERR|\(VER|\(DUM/, split( /[\r\n]/, $stdout ));
	my @hosts = ();
	foreach my $it ( @lines ){
		my @words = split( /\s+/, $it );
		print Dumper( @words );
		msgVerbose( "pushing host $words[2]" );
		push( @hosts, $words[2] );
	}

	# ask each host of this same service to monitor its own urls
	foreach my $host ( @hosts ){
		msgOut( "asking $host for its to-be-monitored URLs" );

		my @others = grep( !/$host/, @hosts );
		$next = $others[0];
		msgOut( "got next='$next'" );
		my $next_label = $next ? "-label next=$next" : "";
		$command = "ssh inlingua-user\@$host services.pl monitor -service $opt_service -urls $next_label -mqtt -http -nocolored $dummy $verbose";
		msgVerbose( $command );
		$stdout = `$command`;
		$rc = $?;
		msgVerbose( $stdout );
		msgVerbose( "rc=$rc" );

		# if one of the monitored urls didn't answer, then alert
		if( $rc && $opt_alert ){
			$command = "ssh inlingua-user\@$host ttp.pl alert -level ALERT -message \"URL DIDN'T ANSWER
Service: $service
Next: $next
Run: 'url_switch.pl -service $service -to $next'\"";
			msgVerbose( $command );
			`$command`;
			$rc = $?;
			msgVerbose( "rc=$rc" );
		}
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
	"environment=s"		=> \$opt_environment,
	"alert!"			=> \$opt_alert )){

		msgOut( "try '$TTPVars->{run}{command}{basename} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpExtern( $defaults );
	Mods::Toops::ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found environment='$opt_environment'" );
msgVerbose( "found alert='".( $opt_alert ? 'true':'false' )."'" );

# service is mandatory
# cannot use Mods::Services::checkServiceOpt() here as we are not tied to a specific host when running from the Linux crontab
msgErr( "service is required, but is not specified" ) if !$opt_service;

if( !Mods::Toops::ttpErrs()){
	doMonitor();
}

Mods::Toops::ttpExit();
