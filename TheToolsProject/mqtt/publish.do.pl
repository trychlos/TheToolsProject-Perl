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

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::MQTT;

my $TTPVars = TTP::TTPVars();

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
my $opt_payload = undef;

# -------------------------------------------------------------------------------------------------
# publish the message
sub doPublish {
	msgOut( "publishing '$opt_topic [$opt_payload]'..." );

	my $mqtt = TTP::MQTT::connect();
	if( $mqtt ){
		$opt_payload //= "";
		if( $opt_retain ){
			$mqtt->retain( $opt_topic, $opt_payload );
		} else {
			$mqtt->publish( $opt_topic, $opt_payload );
		}
		TTP::MQTT::disconnect( $mqtt );
	}

	my $result = true;

	if( $result ){
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
	"verbose!"			=> \$ttp->{run}{verbose},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"topic=s"			=> \$opt_topic,
	"payload=s"			=> \$opt_payload,
	"retain!"			=> \$opt_retain	)){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found topic='$opt_topic'" );
msgVerbose( "found payload='$opt_payload'" );
msgVerbose( "found retain='".( $opt_retain ? 'true':'false' )."'" );

# topic is mandatory
msgErr( "topic is required, but is not specified" ) if !$opt_topic;
msgWarn( "payload is empty, but shouldn't" ) if !defined $opt_payload;

if( !TTP::errs()){
	doPublish();
}

TTP::exit();
