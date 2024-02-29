# @(#) send an alert
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --emitter=<name>        the emitter's name [${emitter}]
# @(-) --level=<name>          the alert level [${level}]
# @(-) --message=<name>        the alert message [${message}]
# @(-) --[no]json              set a JSON file alert to be monitored by the alert daemon [${json}]
# @(-) --[no]mqtt              send the alert on the MQTT bus [${mqtt}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use JSON;
use Sys::Hostname qw( hostname );
use Time::Moment;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	emitter => uc hostname,
	level => 'INFO',
	message => '',
	json => 'yes',
	mqtt => 'yes'
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_message = $defaults->{message};
my $opt_json = true;
my $opt_mqtt = true;

# -------------------------------------------------------------------------------------------------
# send the alert
## as far as we are concerned here, this is just writing a json file in a special directory
sub doJsonAlert {
	Mods::Message::msgOut( "creating a new '$opt_level' json alert..." );

	Mods::Path::makeDirExist( $TTPVars->{config}{toops}{alerts}{dropDir} );
	my $path = File::Spec->catdir( $TTPVars->{config}{toops}{alerts}{dropDir}, Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N.json' ));

	Mods::Toops::jsonWrite({
		emitter => $opt_emitter,
		level => $opt_level,
		message => $opt_message,
		host => uc hostname,
		stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
	}, $path );

	Mods::Message::msgOut( "success" );
}

# -------------------------------------------------------------------------------------------------
# send the alert
## as far as we are concerned here, this is just publishing a MQTT message
sub doMqttAlert {
	Mods::Message::msgOut( "publishing a '$opt_level' alert on MQTT bus..." );

	my $topic = uc hostname;
	$topic .= "/alert";

	my $hash = {
		emitter => $opt_emitter,
		level => $opt_level,
		message => $opt_message,
		host => uc hostname,
		stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
	};
	my $json = JSON->new;
	my $payload = $json->encode( $hash );
	
	print `mqtt.pl publish -topic $topic -payload $payload`;

	Mods::Message::msgOut( "success" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"emitter=s"			=> \$opt_emitter,
	"level=s"			=> \$opt_level,
	"message=s"			=> \$opt_message,
	"json!"				=> \$opt_json,
	"mqtt!"				=> \$opt_mqtt )){

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
Mods::Message::msgVerbose( "found emitter='$opt_emitter'" );
Mods::Message::msgVerbose( "found level='$opt_level'" );
Mods::Message::msgVerbose( "found message='$opt_message'" );
Mods::Message::msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );

# all data are mandatory (and we provide a default value for all but the message)
Mods::Message::msgErr( "emitter is empty, but shouldn't" ) if !$opt_emitter;
Mods::Message::msgErr( "message is empty, but shouldn't" ) if !$opt_message;
Mods::Message::msgErr( "level is empty, but shouldn't" ) if !$opt_level;

# at least one of json or mqtt media mus tbe specified
if( !$opt_json && !$opt_mqtt ){
	Mods::Message::msgErr( "at least one of '--json' or '--mqtt' options must be specified" ) if !$opt_emitter;
}

if( !Mods::Toops::errs()){
	doJsonAlert() if $opt_json;
	doMqttAlert() if $opt_mqtt;
}

Mods::Toops::ttpExit();
