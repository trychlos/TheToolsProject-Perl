# @(#) manage Windows services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --name=<name>           apply to the named service [${name}]
# @(-) --[no]state             query the service state [${state}]
# @(-) --[no]mqtt              publish the result as a MQTT telemetry [${mqtt}]
# @(-) --[no]http              publish the result as a HTTP telemetry [${http}]
#
# @(@) Other options may be provided to this script after a '--' double dash, and will be passed to the 'telemetry.pl publish' verb.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	name => '',
	state => 'no',
	mqtt => 'no',
	http => 'no'
};

my $opt_name = $defaults->{name};
my $opt_state = false;
my $opt_mqtt = false;
my $opt_http = false;

# -------------------------------------------------------------------------------------------------
# query the status of a named service
sub doServiceState {
	msgOut( "querying the '$opt_name' service state..." );
	my $command = "sc query $opt_name";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	my $res = ( $rc == 0 );
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	# note that we do not should execute directly a pipe'd command as we want the return code of the 'sc' one
	# find STATE the line if the command has been successful
	# in case of an error we get the error message in the last non-blank line
	my @lines = split( /[\r\n]/, $stdout );
	my $count = scalar( @lines );
	my $label = undef;
	my $value = undef;
	my $error = undef;
	if( $res ){
		my $state = undef;
		foreach my $line ( @lines ){
			if( $line =~ m/STATE/ ){
				my @words = split( /\s+/, $line );
				$label = $words[scalar( @words )-1];
				$value = "$words[scalar( @words )-2]";
				msgOut( "  $value: $label" );
			}
		}
	} else {
		for( my $i=$count ; $i ; --$i ){
			if( $lines[$i-1] && length $lines[$i-1] ){
				$error = $lines[$i-1];
				last;
			}
		}
		if( !defined $error ){
			$error = "Undefined error";
		}
		msgErr( $error );
	}
	# publish the result in all cases, and notably even if there was an error
	if( $opt_mqtt || $opt_http ){
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		my $metric_value = undef;
		if( $opt_mqtt ){
			msgOut( "publishing to MQTT" );
			$metric_value = $res ? $label : $error;
			$command = "telemetry.pl publish -metric state -value $metric_value ".join( ' ', @ARGV )." -label role=$opt_name -mqtt -nohttp -nocolored $dummy $verbose";
			msgVerbose( $command );
			$stdout = `$command`;
			$rc = $?;
			msgVerbose( $stdout );
			msgVerbose( "rc=$rc" );
		}
		if( $opt_http ){
			msgOut( "publishing to HTTP" );
			# Source: https://learn.microsoft.com/en-us/windows/win32/services/service-status-transitions
			my $states = {
				'1' => 'stopped',
				'2' => 'start_pending',
				'3' => 'stop_pending',
				'4' => 'running',
				'5' => 'continue_pending',
				'6' => 'pause_pending',
				'7' => 'paused'
			};
			foreach my $key ( keys( %{$states} )){
				$metric_value = ( defined $value && $key eq $value ) ? "1" : "0";
				$command = "telemetry.pl publish -metric ttp_service_daemon -value $metric_value ".join( ' ', @ARGV )." -label role=$opt_name -label state=$states->{$key} -nomqtt -http -nocolored $dummy $verbose";
				msgVerbose( $command );
				$stdout = `$command`;
				$rc = $?;
				msgVerbose( $stdout );
				msgVerbose( "rc=$rc" );
			}
		}
	}
	if( $res ){
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
	"name=s"			=> \$opt_name,
	"state!"			=> \$opt_state,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found name='$opt_name'" );
msgVerbose( "found state='".( $opt_state ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# a service name is mandatory when querying its status
msgErr( "'--name' service name is mandatory when querying for a status" ) if $opt_state && !$opt_name;

if( !ttpErrs()){
	doServiceState() if $opt_name && $opt_state;
}

ttpExit();
