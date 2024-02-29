# @(#) get the retained available messages
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]get               get the messages [${get}]
# @(-) --wait=<time>           timeout to wait for messages [${wait}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Net::MQTT::Simple;
use Time::Piece;

use Mods::Constants qw( :all );

my $TTPVars = Mods::Toops::TTPVars();

$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	get => 'no',
	wait => 5
};

my $opt_get = false;
my $opt_wait = $defaults->{wait};

# the MQTT connection
my $mqtt = undef;
my $loop = true;
my $last = 0;
my $count = 0;

# -------------------------------------------------------------------------------------------------
# get and output the retained messages
sub doGetRetained {
	Mods::Toops::msgOut( "getting the retained messages..." );

	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgErr( "no registered broker" ) if !$hostConfig->{MQTT}{broker};
	Mods::Toops::msgErr( "no registered username" ) if !$hostConfig->{MQTT}{username};
	Mods::Toops::msgErr( "no registered password" ) if !$hostConfig->{MQTT}{passwd};

	$mqtt = Net::MQTT::Simple->new( $hostConfig->{MQTT}{broker} );
	if( $mqtt ){
		$mqtt->login( $hostConfig->{MQTT}{username}, $hostConfig->{MQTT}{passwd} );
		Mods::Toops::msgVerbose( "broker login with '$hostConfig->{MQTT}{username}' account" );
		$mqtt->subscribe( '#' => \&doWork );
		while( $loop ){
			$mqtt->tick( 1 );
			my $now = localtime->epoch;
			if( $last && $now - $last > $opt_wait ){
				$loop = false;
			} else {
				sleep( 1 );
			}
		}
	}
	$mqtt->disconnect();
	my $result = true;
	if( $result ){
		Mods::Toops::msgOut( "success: $count got messages" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# triggered on the published message
#  wait 2sec after last received before disconnecting..
sub doWork {
	my ( $topic, $payload, $retain ) = @_;
	if( $retain ){
		print "$topic $payload".EOL;
		Mods::Toops::msgLog( "$topic $payload" );
		$last = localtime->epoch;
		$count += 1;
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
	"get!"				=> \$opt_get,
	"wait=i"			=> \$opt_wait )){

		Mods::Toops::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found get='".( $opt_get ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found wait='$opt_wait'" );

if( !Mods::Toops::errs()){
	doGetRetained() if $opt_get;
}

Mods::Toops::ttpExit();
