# @(#) execute the specified commands for a service
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --host=<name>           search for the service in the given host [${host}]
# @(-) --key=<name[,...]>      the key to be searched for in JSON configuration file, may be specified several times or as a comma-separated list [${key}]
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
	host => '',
	key => ''
};

my $opt_service = $defaults->{service};
my $opt_host = $defaults->{host};
my $opt_key = $defaults->{key};

# the list of keys
my @keys = ();

# -------------------------------------------------------------------------------------------------
# execute the commands registered for the service
# manage macros:
# - HOST
# - SERVICE
sub executeCommands {
	msgOut( "executing '$opt_service [".join( ',', @keys )."]' commands from '$opt_host' host..." );
	my $cmdCount = 0;
	my $host = $opt_host || ttpHost();
	my $config = Mods::Toops::getHostConfig( $host );
	my $hash = ttpVar( \@keys, { config => $config->{Services}{$opt_service} });
	if( $hash && ref( $hash ) eq 'HASH' ){
		my $commands = $hash->{commands};
		if( $commands && ref( $commands ) eq 'ARRAY' && scalar @{$commands} > 0 ){
			foreach my $cmd ( @{$commands} ){
				$cmdCount += 1;
				$cmd =~ s/<HOST>/$host/g;
				$cmd =~ s/<SERVICE>/$opt_service/g;
				msgOut( "  $cmd" );
				my $stdout = `$cmd`;
				my $rc = $?;
				msgLog( "stdout='$stdout'" );
				msgLog( "got rc=$rc" );
			}
		} else {
			msgWarn( "hostConfig->{Services}{$opt_service}[".join( ', ', @keys )."] is not defined, or not an array, or is empty" );
		}
	} else {
		msgWarn( "hostConfig->{Services}{$opt_service}[".join( ', ', @keys )."] is not defined (or not a hash)" );
	}
	msgOut( "$cmdCount executed command(s)" );
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
	"host=s"			=> \$opt_host,
	"key=s@"			=> \$opt_key )){

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
msgVerbose( "found host='$opt_host'" );
@keys = split( /,/, join( ',', @{$opt_key} ));
msgVerbose( "found keys='".join( ',', @keys )."'" );

msgErr( "'--service' service name is required, but not found" ) if !$opt_service;
msgErr( "at least a key is required, but none found" ) if !scalar( @keys );

if( !ttpErrs()){
	executeCommands() if $opt_service && scalar( @keys );
}

ttpExit();
