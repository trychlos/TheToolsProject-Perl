# @(#) publish a message on a topic
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --topic=<name>          the topic to publish in [${topic}]
# @(-) --payload=<name>        the message to be published [${payload}]
# @(-) --[no]retain            with the 'retain' flag (ignored here) [${retain}]
#
# @(@) The topic should be formatted as HOST/subject/subject/content
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Net::MQTT::Simple;

use Mods::Constants qw( :all );

my $TTPVars = Mods::Toops::TTPVars();

$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	topic => '',
	payload => '',
	retain => 'no'
};

my $opt_topic = $defaults->{topic};
my $opt_payload = $defaults->{payload};

# -------------------------------------------------------------------------------------------------
# send the alert
# as far as we are concerned here, this is just writing a json file in a special directory
sub doPublish {
	Mods::Toops::msgOut( "publishing '$opt_topic [$opt_payload]'..." );

	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgErr( "no registered broker" ) if !$hostConfig->{MQTT}{broker};
	Mods::Toops::msgErr( "no registered username" ) if !$hostConfig->{MQTT}{username};
	Mods::Toops::msgErr( "no registered password" ) if !$hostConfig->{MQTT}{passwd};

	my $mqtt = Net::MQTT::Simple->new( $hostConfig->{MQTT}{broker} );
	if( $mqtt ){
		$mqtt->login( $hostConfig->{MQTT}{username}, $hostConfig->{MQTT}{passwd} );
		Mods::Toops::msgVerbose( "broker login with '$hostConfig->{MQTT}{username}' account" );
		if( $opt_retain ){
			$mqtt->retain( $opt_topic, $opt_payload );
		} else {
			$mqtt->publish( $opt_topic, $opt_payload );
		}
		$mqtt->disconnect();
	}

	my $result = true;

	if( $result ){
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
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
	"topic=s"			=> \$opt_topic,
	"payload=s"			=> \$opt_payload,
	"retain!"			=> \$opt_retain	)){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found topic='$opt_topic'" );
Mods::Toops::msgVerbose( "found payload='$opt_payload'" );
Mods::Toops::msgVerbose( "found retain='".( $opt_retain ? 'true':'false' )."'" );

# topic is mandatory
Mods::Toops::msgErr( "topic is required, but is not specified" ) if !$opt_topic;
Mods::Toops::msgWarn( "payload is empty, but shouldn't" ) if !$opt_payload;

if( !Mods::Toops::errs()){
	doPublish();
}

Mods::Toops::ttpExit();