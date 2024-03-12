# @(#) display a configuration varaible on stdout
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --key=<name[,...]>      a comma-separated list of keys to reach the desired value, may be specified several times [${key}]
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

# list of keys
my @keys = ();

# -------------------------------------------------------------------------------------------------
sub displayVar {
	msgOut( "displaying '".join( ', ', @keys )."' variable..." );
	my $hostConfig = Mods::Toops::getHostConfig();
	my @initialKeys = @keys;
	my $serviceConfig = $hostConfig->{Services}{$opt_service};
	my $found = false;
	my $hash = $serviceConfig;
	my $last = pop( @keys );
	foreach my $key ( @keys ){
		if( ref( $hash ) eq 'HASH' && exists $hash->{$key} ){
			$hash = $hash->{$key};
		} elsif( !exists( $hash->{$key} )){
			msgErr( "'$key' key doesn't exist" );
			last;
		} else {
			msgErr( "not a hash to address '$key' key" );
			last;
		}
	}
	if( !ttpErrs()){
		if( exists( $hash->{$last} ) && !ref( $hash->{$last} )){
			print "  ".join( ',', @initialKeys ).": $hash->{$last}".EOL;
		} else {
			msgErr( "'$last' key doesn't exist or doesn't address a scalar value" );
		}
	}
	if( !ttpErrs()){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
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
@keys = split( /,/, join( ',', @{$opt_key} ));
msgVerbose( "found keys='".join( ',', @keys )."'" );

msgErr( "a service is required, but not found" ) if !$opt_service;
msgErr( "at least a key is required, but none found" ) if !scalar( @keys );

if( !ttpErrs()){
	displayVar() if $opt_service && scalar( @keys );
}

ttpExit();
