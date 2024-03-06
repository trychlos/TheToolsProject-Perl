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
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::MQTT;

my $TTPVars = Mods::Toops::TTPVars();

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
	Mods::Message::msgOut( "getting the retained messages..." );

	$mqtt = Mods::MQTT::connect();
	if( $mqtt ){
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
	Mods::MQTT::disconnect( $mqtt );
	my $result = true;
	if( $result ){
		Mods::Message::msgOut( "success: $count got messages" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# triggered on the published message
#  wait 2sec after last received before disconnecting..
sub doWork {
	my ( $topic, $payload, $retain ) = @_;
	if( $retain ){
		print "$topic $payload".EOL;
		Mods::Message::msgLog( "$topic $payload" );
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
Mods::Message::msgVerbose( "found get='".( $opt_get ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found wait='$opt_wait'" );

if( !Mods::Toops::errs()){
	doGetRetained() if $opt_get;
}

Mods::Toops::ttpExit();