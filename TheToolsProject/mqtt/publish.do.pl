# @(#) publish a message on a MQTT topic
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

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::MQTT;

my $TTPVars = Mods::Toops::TTPVars();

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
# publish the message
sub doPublish {
	Mods::Message::msgOut( "publishing '$opt_topic [$opt_payload]'..." );

	my $mqtt = Mods::MQTT::connect();
	if( $mqtt ){
		if( $opt_retain ){
			$mqtt->retain( $opt_topic, $opt_payload );
		} else {
			$mqtt->publish( $opt_topic, $opt_payload );
		}
		Mods::MQTT::disconnect( $mqtt );
	}

	my $result = true;

	if( $result ){
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
	"topic=s"			=> \$opt_topic,
	"payload=s"			=> \$opt_payload,
	"retain!"			=> \$opt_retain	)){

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
Mods::Message::msgVerbose( "found topic='$opt_topic'" );
Mods::Message::msgVerbose( "found payload='$opt_payload'" );
Mods::Message::msgVerbose( "found retain='".( $opt_retain ? 'true':'false' )."'" );

# topic is mandatory
Mods::Message::msgErr( "topic is required, but is not specified" ) if !$opt_topic;
Mods::Message::msgWarn( "payload is empty, but shouldn't" ) if !$opt_payload;

if( !Mods::Toops::errs()){
	doPublish();
}

Mods::Toops::ttpExit();
