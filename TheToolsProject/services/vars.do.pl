# @(#) display a configuration variable on stdout
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

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Services;

my $TTPVars = TTP::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	key => ''
};

my $opt_service = $defaults->{service};
my $opt_keys = [];

# -------------------------------------------------------------------------------------------------
sub displayVar {
	msgOut( "displaying '".join( ',', @{$opt_keys} )."' variable..." );
	#print Dumper( $opt_keys );
	my $hostConfig = TTP::Toops::getHostConfig();
	my @initialKeys = @{$opt_keys};
	my $serviceConfig = TTP::Services::serviceConfig( $hostConfig, $opt_service );
	my $last = undef;
	my $hash = $serviceConfig;
	if( $serviceConfig ){
		my $found = false;
		$last = pop( @{$opt_keys} );
		msgVerbose( "last='$last'" );
		my $count = 0;
		foreach my $key ( @{$opt_keys} ){
			msgVerbose( "key='$key'" );
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
	} else {
		msgErr( "unable to find '$opt_service' service configuration on this host" );
	}
	if( !ttpErrs()){
		if( exists( $hash->{$last} )){
			if( !ref( $hash->{$last} )){
				print "  ".join( ',', @initialKeys ).": $hash->{$last}".EOL;
				$count += 1;
			} elsif( ref( $hash->{$last} ) eq 'ARRAY' ){
				foreach my $it ( @{$hash->{$last}} ){
					print "  ".join( ',', @initialKeys ).": $it".EOL;
					$count += 1;
				}
			} else {
				msgErr( "'$last' key doesn't address a scalar nor an array value" );
			}
		} else {
			msgWarn( "'$last' key doesn't exist" );
		}
	}
	if( !ttpErrs()){
		msgOut( "$count displayed value(s)" );
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
	"key=s@"			=> \$opt_keys )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::Toops::wantsHelp()){
	TTP::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found keys='".join( ',', @{$opt_keys} )."'" );

msgErr( "a service is required, but not found" ) if !$opt_service;
msgErr( "at least a key is required, but none found" ) if !scalar( @{$opt_keys} );

if( !ttpErrs()){
	displayVar() if $opt_service && scalar( @{$opt_keys} );
}

ttpExit();
