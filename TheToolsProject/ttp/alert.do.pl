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
# @(-) --[no]smtp              send the alert by SMTP [${smtp}]
# @(-) --[no]sms               send the alert by SMS [${sms}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use JSON;
use Path::Tiny;
use Time::Moment;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Path;
use Mods::SMTP;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	emitter => ttpHost(),
	level => 'INFO',
	message => ''
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_message = $defaults->{message};
my $opt_json = Mods::Toops::var([ 'alerts', 'withFile', 'enabled' ]);
my $opt_mqtt = Mods::Toops::var([ 'alerts', 'withMqtt', 'enabled' ]);
my $opt_smtp = Mods::Toops::var([ 'alerts', 'withSmtp', 'enabled' ]);
my $opt_sms = Mods::Toops::var([ 'alerts', 'withSms', 'enabled' ]);

$defaults->{json} = $opt_json ? 'yes' : 'no';
$defaults->{mqtt} = $opt_mqtt ? 'yes' : 'no';
$defaults->{smtp} = $opt_smtp ? 'yes' : 'no';
$defaults->{sms} = $opt_sms ? 'yes' : 'no';

# -------------------------------------------------------------------------------------------------
# send the alert by file
# as far as we are concerned here, this is just executing the configured command
# managed macros:
# - DATA: the JSON content
sub doJsonAlert {
	msgOut( "creating a new '$opt_level' json alert..." );
	my $command = Mods::Toops::var([ 'alerts', 'withFile', 'command' ]);
	if( $command ){
		my $dir = Mods::Path::alertsDir();
		if( $dir ){
			Mods::Path::makeDirExist( $dir );
			my $data = {
				emitter => $opt_emitter,
				level => $opt_level,
				message => $opt_message,
				host => ttpHost(),
				stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
			};
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
			my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
			print `$command -nocolored $dummy $verbose`;
			#$? = 256
			$res = $? == 0;
			msgOut( "success" );
		} else {
			msgWarn( "unable to get a dropDir for 'withFile' alerts" );
			msgErr( "alert by file NOT OK" );
		}
	} else {
		msgWarn( "unable to get a command for alerts by file" );
		msgErr( "alert by file NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by mqtt
# as far as we are concerned here, this is just executing the configured command
# managed macros:
# - TOPIC
# - PAYLOAD
# - OPTIONS
sub doMqttAlert {
	msgOut( "publishing a '$opt_level' alert on MQTT bus..." );
	my $command = Mods::Toops::var([ 'alerts', 'withMqtt', 'command' ]);
	my $res = false;
	if( $command ){
		my $topic = ttpHost()."/alert";
		my $data = {
			emitter => $opt_emitter,
			level => $opt_level,
			message => $opt_message,
			host => ttpHost(),
			stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
		};
		my $json = JSON->new;
		my $str = $json->encode( $data );
		# protect the double quotes against the CMD.EXE command-line
		$str =~ s/"/\\"/g;
		$command =~ s/<DATA>/$str/;
		$command =~ s/<SUBJECT>/$topic/;
		my $options = "";
		$command =~ s/<OPTIONS>/$options/;
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		msgWarn( "unable to get a command for alerts by MQTT" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by MQTT NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMS
# Expects have some sort of configuration in Toops json
sub doSmsAlert {
	msgOut( "sending a '$opt_level' alert by SMS..." );
	my $res = false;
	my $command = Mods::Toops::var([ 'alerts', 'withSms', 'command' ]);
	if( $command ){
		my $text = "Hi,
An alert has been raised:
- level is $opt_level
- timestamp is ".localtime->strftime( "%Y-%m-%d %H:%M:%S" )."
- emitter is $opt_emitter
- message is '$opt_message'
Best regards.
";
		my $textfname = Mods::Toops::getTempFileName();
		my $fh = path( $textfname );
		$fh->spew( $text );
		$command =~ s/<OPTIONS>/-textfname $textfname/;
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		Mods::Toops::msgWarn( "unable to get a command for alerts by SMS" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by SMS NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# send the alert by SMTP
# send the mail by executing the configured command
# managed macros:
# - SUBJECT
# - OPTIONS
sub doSmtpAlert {
	msgOut( "publishing a '$opt_level' alert by SMTP..." );
	my $res = false;
	my $command = Mods::Toops::var([ 'alerts', 'withSmtp', 'command' ]);
	if( $command ){
		my $subject = "[$opt_level] Alert";
		my $text = "Hi,
An alert has been raised:
- level is $opt_level
- timestamp is ".localtime->strftime( "%Y-%m-%d %H:%M:%S" )."
- emitter is $opt_emitter
- message is '$opt_message'
Best regards.
";
		my $textfname = Mods::Toops::getTempFileName();
		my $fh = path( $textfname );
		$fh->spew( $text );
		$command =~ s/<SUBJECT>/$subject/;
		$command =~ s/<OPTIONS>/-textfname $textfname/;
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		print `$command -nocolored $dummy $verbose`;
		$res = ( $? == 0 );
	} else {
		msgWarn( "unable to get a command for alerts by SMTP" );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "alert by SMTP NOT OK" );
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
	"smtp!"				=> \$opt_smtp,
	"sms!"				=> \$opt_sms )){

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
msgVerbose( "found emitter='$opt_emitter'" );
msgVerbose( "found level='$opt_level'" );
msgVerbose( "found message='$opt_message'" );
msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found smtp='".( $opt_smtp ? 'true':'false' )."'" );
msgVerbose( "found sms='".( $opt_sms ? 'true':'false' )."'" );

# all data are mandatory (and we provide a default value for all but the message)
msgErr( "emitter is empty, but shouldn't" ) if !$opt_emitter;
msgErr( "message is empty, but shouldn't" ) if !$opt_message;
msgErr( "level is empty, but shouldn't" ) if !$opt_level;
#level must be known
msgErr( "level='$opt_level' is unknown" ) if $opt_level && !Mods::Message::isKnownLevel( $opt_level );

# at least one of json or mqtt media must be specified
if( !$opt_json && !$opt_mqtt && !$opt_smtp && !$opt_sms ){
	msgErr( "at least one of '--json', '--mqtt', '--smtp' or '--sms' options must be specified" ) if !$opt_emitter;
}

if( !ttpErrs()){
	$opt_level = uc $opt_level;
	doJsonAlert() if $opt_json;
	doMqttAlert() if $opt_mqtt;
	doSmtpAlert() if $opt_smtp;
	doSmsAlert() if $opt_sms;
}

ttpExit();
