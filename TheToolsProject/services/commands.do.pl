# @(#) execute the specified commands for a service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --key=<name>            the key to be searched for in JSON configuration file [${key}]
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
	key => ''
};

my $opt_service = $defaults->{service};
my $opt_key = $defaults->{key};

# -------------------------------------------------------------------------------------------------
# execute the commands registered for the service
# manage macros:
# - HOST
# - SERVICE
# - KEY
sub executeStatus {
	msgOut( "executing '$opt_service\\$opt_key' commands..." );
	my $cmdCount = 0;
	my $host = ttpHost();
	my $config = Mods::Toops::getHostConfig();
	my $hash = $config->{Services}{$opt_service}{$opt_key};
	if( $hash && ref( $hash ) eq 'HASH' ){
		my $commands = $hash->{commands};
		if( $commands && ref( $commands ) eq 'ARRAY' && scalar @{$commands} > 0 ){
			foreach my $cmd ( @{$commands} ){
				$cmdCount += 1;
				$cmd =~ s/<HOST>/$host/g;
				$cmd =~ s/<SERVICE>/$opt_service/g;
				$cmd =~ s/<KEY>/$opt_key/g;
				msgOut( "  $cmd" );
				my $stdout = `$cmd`;
				my $rc = $?;
				msgLog( "stdout='$stdout'" );
				msgLog( "got rc=$rc" );
			}
		} else {
			msgWarn( "hostConfig->{Services}{$opt_service}{$opt_key}{commands} is not defined, or not an array, or is empty" );
		}
	} else {
		msgWarn( "hostConfig->{Services}{$opt_service}{$opt_key} is not defined (or not a hash)" );
	}
	msgOut( "$cmdCount executed commands" );
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
	"key=s"				=> \$opt_key )){

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
msgVerbose( "found key='$opt_key'" );

msgErr( "a service is required, but not found" ) if !$opt_service;
msgErr( "a key is required, but not found" ) if !$opt_key;

if( !ttpErrs()){
	executeStatus() if $opt_service && $opt_key;
}

ttpExit();
