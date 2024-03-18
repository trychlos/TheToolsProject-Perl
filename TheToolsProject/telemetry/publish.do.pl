# @(#) publish a metric
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run (ignored here) [${dummy}]
# @(-) --metric=<name>             the metric to be published [${metric}]
# @(-) --label <name=value>        a name=value label, may be specified several times or with a comma-separated list [${label}]
# @(-) --value=<value>             the metric's value [${value}]
# @(-) --[no]http                  publish to HTTP gateway [${http}]
# @(-) --httpPrefix=<prefix>       a prefix to be set on HTTP metrics name [${httpPrefix}]
# @(-) --httpOption <name=value>   an option to be passed to HTTP publication, may be specified several times or with a comma-separated list [${httpOption}]
# @(-) --[no]mqtt                  publish to MQTT bus [${mqtt}]
# @(-) --mqttPrefix=<prefix>       a prefix to be set on MQTT metrics name [${mqttPrefix}]
# @(-) --mqttOption <name=value>   an option to be passed to MQTT publication, may be specified several times or with a comma-separated list [${httpOption}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
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
	httpOption => '',
	mqttPrefix => '',
	mqttOption => ''
};

my $opt_metric = $defaults->{metric};
my $opt_label = $defaults->{label};
my $opt_value = undef;
my $opt_mqtt = ttpVar([ 'Telemetry', 'withMqtt', 'enabled' ]);
my $opt_http = ttpVar([ 'Telemetry', 'withHttp', 'enabled' ]);
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
	my $res = Mods::Telemetry::httpPublish( $opt_metric, $opt_value, \@labels, { httpPrefix => $opt_httpPrefix, httpOptions => \@httpOptions });
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
	my $res = Mods::Telemetry::mqttPublish( $opt_metric, $opt_value, \@labels, { mqttPrefix => $opt_mqttPrefix, mqttOptions => \@mqttOptions });
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
	"metric=s"			=> \$opt_metric,
	"label=s@"			=> \$opt_label,
	"value=s"			=> \$opt_value,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"httpPrefix=s"		=> \$opt_httpPrefix,
	"httpOption=s@"		=> \$opt_httpOption,
	"mqttPrefix=s"		=> \$opt_mqttPrefix,
	"mqttOption=s@"		=> \$opt_mqttOption	)){

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

if( !ttpErrs()){
	doMqttPublish() if $opt_mqtt;
	doHttpPublish() if $opt_http;
}

ttpExit();
