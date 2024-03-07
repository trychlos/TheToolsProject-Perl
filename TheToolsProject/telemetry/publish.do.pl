# @(#) publish a metric
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --metric=<name>         the metric to be published [${metric}]
# @(-) --label=<name=value>    a name=value label, may be specified several times or with a comma-separated list [${label}]
# @(-) --value=<value>         the metric's value [${value}]
# @(-) --[no]mqtt              publish to MQTT bus [${mqtt}]
# @(-) --[no]http              publish to HTTP gateway [${http}]
# @(-) --httpPrefix=<prefix>   a prefix to be set on HTTP metrics name [${httpPrefix}]
# @(-) --mqttPrefix=<prefix>   a prefix to be set on MQTT metrics name [${mqttPrefix}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Telemetry;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	metric => '',
	label => '',
	value => '',
	httpPrefix => '',
	mqttPrefix => ''
};

my $opt_metric = $defaults->{metric};
my $opt_label = $defaults->{label};
my $opt_value = undef;
my $opt_mqtt = Mods::Toops::var([ 'Telemetry', 'withMqtt', 'enabled' ]);
my $opt_http = Mods::Toops::var([ 'Telemetry', 'withHttp', 'enabled' ]);
my $opt_httpPrefix = $defaults->{httpPrefix};
my $opt_mqttPrefix = $defaults->{mqttPrefix};

$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{http} = $opt_http ? 'yes' : 'no';

# a list of name=value pairs
my @labels = ();

# -------------------------------------------------------------------------------------------------
# send the metric
# this requires a telemetry gateway, which is handle by the Telemetry package
sub doHttpPublish {
	Mods::Message::msgOut( "publishing '$opt_metric' metric to HTTP gateway..." );
	my $res = Mods::Telemetry::httpPublish( $opt_metric, $opt_value, \@labels, { httpPrefix => $opt_httpPrefix });
	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the metric
sub doMqttPublish {
	Mods::Message::msgOut( "publishing '$opt_metric' metric to MQTT bus..." );
	my $res = Mods::Telemetry::mqttPublish( $opt_metric, $opt_value, \@labels, { mqttPrefix => $opt_mqttPrefix });
	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
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
	"metric=s"			=> \$opt_metric,
	"label=s@"			=> \$opt_label,
	"value=s"			=> \$opt_value,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"mqttPrefix=s"		=> \$opt_mqttPrefix )){

		Mods::Message::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Message::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found metric='$opt_metric'" );
@labels = split( /,/, join( ',', @{$opt_label} ));
Mods::Message::msgVerbose( "found label='".join( ',', @labels )."'" );
Mods::Message::msgVerbose( "found value='".( defined $opt_value ? $opt_value : '(undef)' )."'" );
Mods::Message::msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found httpPrefix='$opt_httpPrefix'" );
Mods::Message::msgVerbose( "found mqttPrefix='$opt_mqttPrefix'" );

# metric and values are mandatory
Mods::Message::msgErr( "metric is required, but is not specified" ) if !$opt_metric;
Mods::Message::msgErr( "value is required, but is not specified" ) if !defined $opt_value;

# if labels are specified, check that each one is of the 'name=value' form
foreach my $label ( @labels ){
	my @words = split( /=/, $label );
	if( scalar @words != 2 || !$words[0] || !$words[1] ){
		Mods::Message::msgErr( "label '$label' doesn't appear of the 'name=value' form" );
	}
}
Mods::Message::msgOut( "do not publish anything as neither '--mqtt' nor '--http' are set" ) if !$opt_mqtt && !$opt_http;

if( !Mods::Toops::errs()){
	doMqttPublish() if $opt_mqtt;
	doHttpPublish() if $opt_http;
}

Mods::Toops::ttpExit();
