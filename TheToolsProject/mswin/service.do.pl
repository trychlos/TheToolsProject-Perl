# @(#) manage Windows services
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]list              list the managed services [${list}]
# @(-) --name=<name>           acts on the named service [${name}]
# @(-) --[no]state             query the service state [${state}]
# @(-) --[no]mqtt              publish the metrics to the (MQTT-based) messaging system [${mqtt}]
# @(-) --[no]http              publish the metrics to the (HTTP-based) Prometheus PushGateway system [${http}]
# @(-) --[no]text              publish the metrics to the (text-based) Prometheus TextFile Collector system [${text}]
# @(-) --prepend=<name=value>  label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${prepend}]
# @(-) --append=<name=value>   label to be appended to the telemetry metrics, may be specified several times or as a comma-separated list [${append}]
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

use TTP::Metric;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	list => 'no',
	name => '',
	state => 'no',
	mqtt => 'no',
	http => 'no',
	text => 'no',
	prepend => '',
	append => ''
};

my $opt_list = false;
my $opt_name = $defaults->{name};
my $opt_state = false;
my $opt_mqtt = false;
my $opt_http = false;
my $opt_text = false;
my @opt_prepends = ();
my @opt_appends = ();

# Source: https://learn.microsoft.com/en-us/windows/win32/services/service-status-transitions
my $serviceStates = {
	'1' => 'stopped',
	'2' => 'start_pending',
	'3' => 'stop_pending',
	'4' => 'running',
	'5' => 'continue_pending',
	'6' => 'pause_pending',
	'7' => 'paused'
};

# -------------------------------------------------------------------------------------------------
# list the managed Win32 services
# provides a case-insensitive sorted list of services

sub doServicesList {
	msgOut( "querying the services list..." );
	my $command = "sc query | find \"SERVICE_NAME:\"";
	msgVerbose( $command );
	my $stdout = `$command`;
	my $rc = $?;
	my $res = ( $rc == 0 );
	msgVerbose( $stdout );
	msgVerbose( "rc=$rc" );
	my @list = split( /[\r\n]/, $stdout );
	my $count = 0;
	foreach my $it ( sort { "\L$a" cmp "\L$b" } @list ){
		my @words = split( /\s+/, $it );
		print " $words[1]".EOL;
		$count += 1;
	}
	if( $res ){
		msgOut( "$count found managed service(s)" );
	} else {
		msgErr( "NOT OK" );
	}
}

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
	if( $opt_mqtt || $opt_http || $opt_text ){
		my @labels = ( @opt_prepends, "role=$opt_name", @opt_appends );
		TTP::Metric->new( $ttp, {
			name => 'state',
			value => $res ? $label : $error,
			labels => \@labels
		})->publish({
			mqtt => $opt_mqtt
		});
		foreach my $key ( keys( %{$serviceStates} )){
			my @labels = ( @opt_prepends, "role=$opt_name", "state=$serviceStates->{$key}", @opt_appends );
			TTP::Metric->new( $ttp, {
				name => 'service_state',
				value => ( defined $value && $key eq $value ) ? '1' : '0',
				type => 'gauge',
				help => 'Win32 service status',
				labels => \@labels
			})->publish({
				http => $opt_http,
				text => $opt_text
			});
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"list!"				=> \$opt_list,
	"name=s"			=> \$opt_name,
	"state!"			=> \$opt_state,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"text!"				=> \$opt_text,
	"prepend=s@"		=> \@opt_prepends,
	"append=s@"			=> \@opt_appends )){

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
msgVerbose( "found list='".( $opt_list ? 'true':'false' )."'" );
msgVerbose( "found name='$opt_name'" );
msgVerbose( "found state='".( $opt_state ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "found text='".( $opt_text ? 'true':'false' )."'" );
@opt_prepends = split( /,/, join( ',', @opt_prepends ));
msgVerbose( "found prepends='".join( ',', @opt_prepends )."'" );
@opt_appends = split( /,/, join( ',', @opt_appends ));
msgVerbose( "found appends='".join( ',', @opt_appends )."'" );

# a service name is mandatory when querying its status
msgErr( "'--name' service name is mandatory when querying for a status" ) if $opt_state && !$opt_name;

if( !TTP::errs()){
	doServicesList() if $opt_list;
	doServiceState() if $opt_name && $opt_state;
}

TTP::exit();
