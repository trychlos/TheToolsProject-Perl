# @(#) get the MQTT retained available messages
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

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::MQTT;

my $TTPVars = TTP::TTPVars();

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
	msgOut( "getting the retained messages..." );

	$mqtt = TTP::MQTT::connect();
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
	TTP::MQTT::disconnect( $mqtt );
	my $result = true;
	if( $result ){
		msgOut( "success: $count got messages" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# triggered on the published message
#  wait 2sec after last received before disconnecting..
sub doWork {
	my ( $topic, $payload, $retain ) = @_;
	if( $retain ){
		print "$topic $payload".EOL;
		msgLog( "$topic $payload" );
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

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found get='".( $opt_get ? 'true':'false' )."'" );
msgVerbose( "found wait='$opt_wait'" );

if( !TTP::errs()){
	doGetRetained() if $opt_get;
}

TTP::exit();
