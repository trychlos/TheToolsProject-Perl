# @(#) send a new alert
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --emitter=<name>        the emitter's name [${emitter}]
# @(-) --level=<name>          the alert level [${level}]
# @(-) --message=<name>        the alert message [${message}]
#
# @(xxx) --setdest=<name>        set the alert destination in replacement of the defaults [${setdest}]
# @(xxx) --adddest=<name>        add an alert destination to the defaults [${adddest}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Sys::Hostname qw( hostname );
use Time::Moment;

use Mods::Constants qw( :all );

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	emitter => '',
	level => 'INFO',
	message => ''
};

my $opt_emitter = $defaults->{emitter};
my $opt_level = INFO;
my $opt_message = $defaults->{message};

# -------------------------------------------------------------------------------------------------
# send the alert
# as far as we are concerned here, this is just writing a json file in a special directory
sub doSend {
	Mods::Toops::msgOut( "sending a '$opt_level' alert..." );

	my $path = File::Spec->catdir( $TTPVars->{config}{site}{toops}{alerts}{dropDir}, Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N.json' ));

	Mods::Toops::jsonWrite({
		emitter => $opt_emitter,
		level => $opt_level,
		message => $opt_message,
		host => uc hostname,
		stamp => localtime->strftime( "%Y-%m-%d %H:%M:%S" )
	}, $path );

	Mods::Toops::msgOut( "success" );
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
	"message=s"			=> \$opt_message )){

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
Mods::Toops::msgVerbose( "found emitter='$opt_emitter'" );
Mods::Toops::msgVerbose( "found level='$opt_level'" );
Mods::Toops::msgVerbose( "found message='$opt_message'" );

# we accept empty vars here, but still emit a warn
Mods::Toops::msgWarn( "emitter is empty, but shouldn't" ) if !$opt_emitter;
Mods::Toops::msgWarn( "message is empty, but shouldn't" ) if !$opt_message;

# level is mandatory (and we provide a default value)
Mods::Toops::msgErr( "level is empty, but shouldn't" ) if !$opt_level;

if( !Mods::Toops::errs()){
	doSend();
}

Mods::Toops::ttpExit();
