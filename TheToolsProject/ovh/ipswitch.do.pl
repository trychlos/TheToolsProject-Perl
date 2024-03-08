# @(#) switch an IP service to another server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --ip=<name>             the IP OVH service name [${ip}]
# @(-) --to=<server>           the target server OVH service name [${to}]
# @(-) --[no]wait              wait until the IP is said routed [${wait}]
# @(-) --url=<url>             the URL to be tested for X-Sent-By header [${url}]
# @(-) --timeout=<seconds>     wait timeout [${timeout}]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;
use URI::Escape;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Ovh;
use Mods::Services;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	ip => '',
	to => '',
	wait => 'no',
	url => '',
	timeout => 300
};

my $opt_ip = $defaults->{ip};
my $opt_to = $defaults->{to};
my $opt_wait = false;
my $opt_url = $defaults->{url};
my $opt_timeout = $defaults->{timeout};

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names
sub doSwitchIP {
	Mods::Message::msgOut( "switching '$opt_ip' service to '$opt_to' server..." );
	my $res = false;
	my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";

	# check that the requested desired server is not already the routed one
	my $out = Mods::Toops::ttpFilter( `ovh.pl ipget -ip $opt_ip -routed -nocolored $verbose $dummy` );
	my @words = split( /\s+/, $out->[0] );
	my $current = $words[1];
	if( $current eq $opt_to ){
		Mods::Message::msgWarn( "the specified '$opt_ip' is already routed to '$opt_to'" );
		$res = true;
	} else {
		Mods::Message::msgVerbose( "current routed server is '$current'" );
		my $api = Mods::Ovh::connect();
		if( $api ){
			# we need the IP block
			$out = Mods::Toops::ttpFilter( `ovh.pl ipget -ip $opt_ip -address -nocolored $verbose $dummy` );
			@words = split( /\s+/, $out->[0] );
			my $ip = $words[1];
			Mods::Message::msgVerbose( "IP address is '$ip'" );
			# check that the requested target server is willing to accept this IP - answer is empty if ok
			my $url = "/dedicated/server/$opt_to/ipCanBeMovedTo?ip=".uri_escape( $ip );
			my $answer = Mods::Ovh::getAnswerByPath( $api, $url );
			# ask for the move
			if( $answer->status() == 200 && !$answer->content()){
				$url = "/dedicated/server/$opt_to/ipMove";
				$answer = Mods::Ovh::postByPath( $api, $url, { ip => $ip });
				if( $answer->status() == 200 ){
					if( $opt_wait ){
						my $start = localtime->epoch;
						my $end = false;
						my $timeout = false;
						print "waiting for move";
						do {
							print ".";
							sleep 2;
							$out = Mods::Toops::ttpFilter( `ovh.pl ipget -ip $opt_ip -routed -nocolored $verbose $dummy` );
							@words = split( /\s+/, $out->[0] );
							$current = $words[1];
							if( $current eq $opt_to ){
								$end = true;
							} elsif( localtime->epoch - $start > $opt_timeout ){
								$timeout = true;
							}
						} while( !$end && !$timeout );
						print EOL;
						if( $end ){
							Mods::Message::msgOut( "OVH API says that IP is switched after ".( localtime->epoch - $start )." sec." );
							if( $opt_url ){
								print "waiting for target machine answer";
								$end = false;
								do {
									print ".";
									sleep 2;
									$out = `http.pl get -url $opt_url -header X-Sent-By -ignore -nocolored $dummy $verbose`;
									my @grepped = grep( / got /, split( /[\r\n]/, $out ));
									my $line = $grepped[0];
									$line =~ s/^[^=]+='([^']+)'$/$1/;
									Mods::Message::msgVerbose( "got '$line'" );
									if( $line eq $opt_to ){
										$end = true;
									} elsif( localtime->epoch - $start > $opt_timeout ){
										$timeout = true;
									}
								} while( !$end && !$timeout );
								print EOL;
								if( $end ){
									Mods::Message::msgOut( "URL is actually switched after ".( localtime->epoch - $start )." sec." );
								}
							}
							$res = true;
						}
						if( $timeout ){
							Mods::Message::msgWarn( "timeout ($opt_timeout sec.) while waiting for actual move, still setting result='true'" );
							$res = true;
						}
					} else {
						Mods::Message::msgVerbose( "do not wait for actual move" );
						$res = true;
					}
				} else {
					Mods::Toops::msgErr( "an error occurred when requesting the move: ".$answer->error());
				}
			} else {
				Mods::Toops::msgErr( "the target server is not willing to get the '$opt_ip' address service" );
			}
		}
	}
	if( $res ){
		Mods::Message::msgOut( "successfully switched to $opt_to" );
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
	"ip=s"				=> \$opt_ip,
	"to=s"				=> \$opt_to,
	"wait!"				=> \$opt_wait,
	"url=s"				=> \$opt_url,
	"timeout=i"			=> \$opt_timeout )){

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
Mods::Message::msgVerbose( "found ip='$opt_ip'" );
Mods::Message::msgVerbose( "found to='$opt_to'" );
Mods::Message::msgVerbose( "found wait='".( $opt_wait ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found url='$opt_url'" );
Mods::Message::msgVerbose( "found timeout='$opt_timeout'" );

Mods::Message::msgErr( "ip service is mandatory, not specified" ) if !$opt_ip;
Mods::Message::msgErr( "target server service is mandatory, not specified" ) if !$opt_to;

if( !Mods::Toops::errs()){
	doSwitchIP();
}

Mods::Toops::ttpExit();
