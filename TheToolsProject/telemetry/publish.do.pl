# @(#) publish a metric
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --metric=<name>             the metric to be published [${metric}]
# @(-) --label <name=value>        a name=value label, may be specified several times or with a comma-separated list [${label}]
# @(-) --value=<value>             the metric's value [${value}]
# @(-) --[no]http                  publish to HTTP gateway [${http}]
# @(-) --httpPrefix=<prefix>       a prefix to be set on HTTP metrics name [${httpPrefix}]
# @(-) --httpOption <name=value>   an option to be passed to HTTP publication, may be specified several times or with a comma-separated list [${httpOption}]
# @(-) --[no]mqtt                  publish to MQTT bus [${mqtt}]
# @(-) --mqttPrefix=<prefix>       a prefix to be set on MQTT metrics name [${mqttPrefix}]
# @(-) --mqttOption <name=value>   an option to be passed to MQTT publication, may be specified several times or with a comma-separated list [${mqttOption}]
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

use TTP::Telemetry;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	metric => '',
	label => '',
	value => '',
	httpPrefix => '',
	httpOption => '',
	mqttPrefix => '',
	mqttOption => ''
};

my $opt_metric = $defaults->{metric};
my $opt_label = $defaults->{label};
my $opt_value = undef;
my $opt_mqtt = TTP::var([ 'Telemetry', 'withMqtt', 'enabled' ]);
my $opt_http = TTP::var([ 'Telemetry', 'withHttp', 'enabled' ]);
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_httpOption = $defaults->{httpOption};
my $opt_mqttPrefix = $defaults->{mqttPrefix};
my $opt_mqttOption = $defaults->{mqttOption};

$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{http} = $opt_http ? 'yes' : 'no';

# lists of name=value pairs
my @labels = ();
my @httpOptions = ();
my @mqttOptions = ();

# -------------------------------------------------------------------------------------------------
# send the metric
# this requires a telemetry gateway, which is handle by the Telemetry package
sub doHttpPublish {
	msgOut( "publishing '$opt_metric' metric to HTTP gateway..." );
	my $res = TTP::Telemetry::httpPublish( $opt_metric, $opt_value, \@labels, { httpPrefix => $opt_httpPrefix, httpOptions => \@httpOptions });
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the metric
sub doMqttPublish {
	msgOut( "publishing '$opt_metric' metric to MQTT bus..." );
	my $res = TTP::Telemetry::mqttPublish( $opt_metric, $opt_value, \@labels, { mqttPrefix => $opt_mqttPrefix, mqttOptions => \@mqttOptions });
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
	"metric=s"			=> \$opt_metric,
	"label=s@"			=> \$opt_label,
	"value=s"			=> \$opt_value,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"httpOption=s@"		=> \$opt_httpOption,
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"mqttOption=s@"		=> \$opt_mqttOption	)){

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
msgVerbose( "found metric='$opt_metric'" );
@labels = split( /,/, join( ',', @{$opt_label} ));
msgVerbose( "found labels='".join( ',', @labels )."'" );
msgVerbose( "found value='".( defined $opt_value ? $opt_value : '(undef)' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "found httpPrefix='$opt_httpPrefix'" );
@httpOptions = split( /,/, join( ',', @{$opt_httpOption} ));
msgVerbose( "found httpOptions='".join( ',', @httpOptions )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found mqttPrefix='$opt_mqttPrefix'" );
@mqttOptions = split( /,/, join( ',', @{$opt_mqttOption} ));
msgVerbose( "found mqttOptions='".join( ',', @mqttOptions )."'" );

# metric and values are mandatory
msgErr( "'--metric' metric option is required, but is not specified" ) if !$opt_metric;
msgErr( "'--value' value option is required, but is not specified" ) if !defined $opt_value;

# if labels are specified, check that each one is of the 'name=value' form
foreach my $label ( @labels ){
	my @words = split( /=/, $label );
	if( scalar @words != 2 || !$words[0] || !$words[1] ){
		msgErr( "label '$label' doesn't appear of the 'name=value' form" );
	}
}
msgOut( "do not publish anything as neither '--mqtt' nor '--http' are set" ) if !$opt_mqtt && !$opt_http;

if( !TTP::errs()){
	doMqttPublish() if $opt_mqtt;
	doHttpPublish() if $opt_http;
}

TTP::exit();
