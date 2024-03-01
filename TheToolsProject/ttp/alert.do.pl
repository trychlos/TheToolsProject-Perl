# @(#) send an alert
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --emitter=<name>        the emitter's name [${emitter}]
# @(-) --level=<level>         the alert level [${level}]
# @(-) --message=<name>        the alert message [${message}]
# @(-) --[no]json              set a JSON file alert to be monitored by the alert daemon [${json}]
# @(-) --[no]mqtt              send the alert on the MQTT bus [${mqtt}]
# @(-) --[no]mail              send the alert by email [${mail}]
# @(-) --[no]sms               send the alert by SMS [${sms}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use JSON;
use Sys::Hostname qw( hostname );
use Time::Moment;

use Mods::Constants qw( :all );
use Mods::Mail;
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
	message => ''
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_message = $defaults->{message};
my $opt_json = Mods::Toops::var([ 'alerts', 'withFile', 'enabled' ]);
my $opt_mqtt = Mods::Toops::var([ 'alerts', 'withMqtt', 'enabled' ]);
my $opt_mail = Mods::Toops::var([ 'alerts', 'withMail', 'enabled' ]);
my $opt_sms = Mods::Toops::var([ 'alerts', 'withSms', 'enabled' ]);

$defaults->{json} = $opt_json ? 'yes' : 'no';
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{mail} = $opt_mail ? 'yes' : 'no';
$defaults->{sms} = $opt_sms ? 'yes' : 'no';

# -------------------------------------------------------------------------------------------------
# send the alert by file
# as far as we are concerned here, this is just writing a json file in a special directory
sub doJsonAlert {
	Mods::Message::msgOut( "creating a new '$opt_level' json alert..." );
	my $dir = Mods::Toops::var([ 'alerts', 'withFile', 'dropDir' ]);
	if( $dir ){
		Mods::Path::makeDirExist( $dir );
		my $path = File::Spec->catdir( $dir, Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N.json' ));
		Mods::Toops::jsonWrite({
			emitter => $opt_emitter,
			level => $opt_level,
			message => $opt_message,
			host => uc hostname,
			stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
		}, $path );
		Mods::Message::msgOut( "success" );

	} else {
		Mods::Message::msgWarn( "unable to get an alerts drop directory" );
		Mods::Message::msgErr( "alert by file NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by email
# send the mail through the designated mail gateway
sub doMailAlert {
	Mods::Message::msgOut( "publishing a '$opt_level' alert by email..." );
	my $res = false;
	my $gateway = Mods::Toops::var([ 'alerts', 'withMail', 'gateway' ]);
	if( $gateway ){
		my $smtpGateway = Mods::Toops::var([ $gateway ]);
		if( $smtpGateway ){
			my $mailto = Mods::Toops::var([ 'alerts', 'withMail', 'mailto' ]);
			if( !$mailto || !scalar @{$mailto} ){
				$mailto = [ 'admin@blingua.fr' ];
			}
			my $message = "Hi,
Level is $opt_level
Stamp is ".localtime->strftime( "%Y-%m-%d %H:%M:%S" )."
Emitter is $opt_emitter
";
			$res = Mods::Mail::send({
				subject => 'Alert',
				message => $message,
				mailto => $mailto
			}, $smtpGateway );
		} else {
			Mods::Message::msgWarn( "smtpGateway '$gateway' not defined or not found" );
		}
	} else {
		Mods::Message::msgWarn( "alerts/withMail/gateway is not defined neither in toops nor in host configuration" );
	}
	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "alert by email NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just publishing a MQTT message with the special 'alert' topic
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
	my $res = $?;

	if( $res == 0 ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "alert by Mqtt NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just publishing a MQTT message with the special 'alert' topic
sub doSmsAlert {
	Mods::Message::msgOut( "publishing a '$opt_level' alert by SMS..." );
	my $res = false;

	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "alert by SMS NOT OK" );
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
	"emitter=s"			=> \$opt_emitter,
	"level=s"			=> \$opt_level,
	"message=s"			=> \$opt_message,
	"json!"				=> \$opt_json,
	"mqtt!"				=> \$opt_mqtt,
	"mail!"				=> \$opt_mail,
	"sms!"				=> \$opt_sms )){

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
Mods::Message::msgVerbose( "found mail='".( $opt_mail ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found sms='".( $opt_sms ? 'true':'false' )."'" );

# all data are mandatory (and we provide a default value for all but the message)
Mods::Message::msgErr( "emitter is empty, but shouldn't" ) if !$opt_emitter;
Mods::Message::msgErr( "message is empty, but shouldn't" ) if !$opt_message;
Mods::Message::msgErr( "level is empty, but shouldn't" ) if !$opt_level;
#level must be known
Mods::Message::msgErr( "level='$opt_level' is unknown" ) if $opt_level && !Mods::Message::isKnownLevel( $opt_level );

# at least one of json or mqtt media must be specified
if( !$opt_json && !$opt_mqtt && !$opt_mail && !$opt_sms ){
	Mods::Message::msgErr( "at least one of '--json', '--mqtt', '--mail' or '--sms' options must be specified" ) if !$opt_emitter;
}

if( !Mods::Toops::errs()){
	$opt_level = uc $opt_level;
	doJsonAlert() if $opt_json;
	doMqttAlert() if $opt_mqtt;
	doMailAlert() if $opt_mail;
	doSmsAlert() if $opt_sms;
}

Mods::Toops::ttpExit();
