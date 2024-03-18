#!/usr/bin/perl
# @(#) Monitor a daemon and publish the result as a telemetry
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --json=<filename>       the name of the JSON configuration file of this daemon [${json}]
# @(-) --metric=<name>         the metric to be published [${metric}]
# @(-) --label <name=value>    a name=value label, may be specified several times or with a comma-separated list [${label}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Getopt::Long;

use Mods::Toops;
use Mods::Constants qw( :all );
use Mods::Message qw( :all );

# TTP initialization
my $TTPVars = Mods::Toops::initExtern();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => '',
	metric => '',
	label => ''
};

my $opt_json = $defaults->{json};

# the array of the labels
my @labels = ();

# -------------------------------------------------------------------------------------------------
# test for the presence of the specified daemon
#  publishing the result as a telemetry
sub doStatus {
	msgOut( "testing for '$opt_json' specified daemon..." );

	# get and execute the commands for this target state
	my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
	my $command = "daemon.pl status -json $opt_json -nocolored $dummy $verbose";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	my $value = ( $rc == 0 ) ? "1" : "0";
	my $labels = "";
	foreach my $it ( @labels ){
		$labels .= " -label $it";
	}
	$command = "telemetry.pl publish -metric $opt_metric -value $value $labels -nomqtt -http -nocolored $dummy $verbose";
	msgVerbose( $command );
	$stdout = `$command`;
	$rc = $?;
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );

	msgOut( "done" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"json=s"			=> \$opt_json,
	"metric=s"			=> \$opt_metric,
	"label=s@"			=> \$opt_label )){

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
msgVerbose( "found json='$opt_json'" );
msgVerbose( "found metric='$opt_metric'" );
@labels = split( /,/, join( ',', @{$opt_label} ));
msgVerbose( "found labels='".join( ',', @labels )."'" );

msgErr( "'--json' JSON configuration filename is mandatory, but has not been found" ) if !$opt_json;
msgErr( "'--metric' metric is mandatory, but has not been found" ) if !$opt_metric;

if( !Mods::Toops::ttpErrs()){
	doStatus();
}

Mods::Toops::ttpExit();
