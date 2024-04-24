# @(#) switch an IP service to another server
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --ip=<name>             the IP OVH service name [${ip}]
# @(-) --to=<server>           the target server OVH service name [${to}]
# @(-) --[no]wait              wait until the IP is said routed [${wait}]
# @(-) --url=<url>             the URL to be tested for X-Sent-By header [${url}]
# @(-) --sender=<sender>       the expected sender searched in X-Sent-By header [${sender}]
# @(-) --timeout=<seconds>     wait timeout [${timeout}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use URI::Escape;
use Time::Piece;

use TTP::Ovh;
use TTP::Service;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	ip => '',
	to => '',
	wait => 'no',
	url => '',
	sender => '',
	timeout => 300
};

my $opt_ip = $defaults->{ip};
my $opt_to = $defaults->{to};
my $opt_wait = false;
my $opt_url = $defaults->{url};
my $opt_sender = $defaults->{sender};
my $opt_timeout = $defaults->{timeout};

# -------------------------------------------------------------------------------------------------
# display the server the service IP is attached to
# the service must be configured with a 'ovh' entry with 'ip' and 'server' OVH service names

sub doSwitchIP {
	msgOut( "switching '$opt_ip' service to '$opt_to' host..." );
	my $res = false;
	my $dummy = $ttp->{run}{dummy} ? "-dummy" : "-nodummy";
	my $verbose = $ttp->{run}{verbose} ? "-verbose" : "-noverbose";

	# check that the requested desired server is not already the routed one
	my $out = ttpFilter( `ovh.pl ipget -ip $opt_ip -routed -nocolored $verbose $dummy` );
	my @words = split( /\s+/, $out->[0] );
	my $current = $words[1];
	if( $current eq $opt_to ){
		msgWarn( "the specified '$opt_ip' is already routed to '$opt_to'" );
		$res = true;
	} else {
		msgVerbose( "current routed server is '$current'" );
		my $api = TTP::Ovh::connect();
		if( $api ){
			# we need the IP block
			$out = ttpFilter( `ovh.pl ipget -ip $opt_ip -address -nocolored $verbose $dummy` );
			@words = split( /\s+/, $out->[0] );
			my $ip = $words[1];
			msgVerbose( "IP address is '$ip'" );
			# check that the requested target server is willing to accept this IP - answer is empty if ok
			my $url = "/dedicated/server/$opt_to/ipCanBeMovedTo?ip=".uri_escape( $ip );
			my $answer = TTP::Ovh::getAnswerByPath( $api, $url );
			# ask for the move
			if( $answer->status() == 200 && !$answer->content()){
				$url = "/dedicated/server/$opt_to/ipMove";
				$answer = TTP::Ovh::postByPath( $api, $url, { ip => $ip });
				if( $answer->status() == 200 ){
					if( $opt_wait ){
						my $start = localtime->epoch;
						my $end = false;
						my $timeout = false;
						print "waiting for IP move";
						do {
							print ".";
							sleep 1;
							$out = ttpFilter( `ovh.pl ipget -ip $opt_ip -routed -nocolored $dummy $verbose` );
							msgLog( "ttpFilter() returns: '".Dumper( $out )."'" );
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
							msgOut( "OVH API says that IP is switched after ".( localtime->epoch - $start )." sec." );
							if( $opt_url ){
								print "waiting for target machine answer";
								$end = false;
								do {
									print ".";
									sleep 1;
									$out = ttpFilter( `http.pl get -url $opt_url -header X-Sent-By -accept [1-3].. -nocolored $dummy $verbose` );
									msgLog( "ttpFilter() returns: '".Dumper( $out )."'" );
									@words = split( /\s+/, $out->[0] );
									$line = $words[1];
									if( $line eq $opt_sender ){
										$end = true;
									} elsif( localtime->epoch - $start > $opt_timeout ){
										$timeout = true;
									}
								} while( !$end && !$timeout );
								print EOL;
								if( $end ){
									msgOut( "URL is actually switched after ".( localtime->epoch - $start )." sec." );
								}
							}
							$res = true;
						}
						if( $timeout ){
							msgWarn( "timeout ($opt_timeout sec.) while waiting for actual move, still setting result='true'" );
							$res = true;
						}
					} else {
						msgVerbose( "do not wait for actual move" );
						$res = true;
					}
				} else {
					msgErr( "an error occurred when requesting the move: ".$answer->error());
				}
			} else {
				msgErr( "the target server is not willing to get the '$opt_ip' address service" );
			}
		}
	}
	if( $res ){
		msgOut( "successfully switched to $opt_to" );
	} else {
		msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"ip=s"				=> \$opt_ip,
	"to=s"				=> \$opt_to,
	"wait!"				=> \$opt_wait,
	"url=s"				=> \$opt_url,
	"sender=s"			=> \$opt_sender,
	"timeout=i"			=> \$opt_timeout )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found ip='$opt_ip'" );
msgVerbose( "found to='$opt_to'" );
msgVerbose( "found wait='".( $opt_wait ? 'true':'false' )."'" );
msgVerbose( "found url='$opt_url'" );
msgVerbose( "found sender='$opt_sender'" );
msgVerbose( "found timeout='$opt_timeout'" );

msgErr( "ip service is mandatory, not specified" ) if !$opt_ip;
msgErr( "target server service is mandatory, not specified" ) if !$opt_to;
msgErr( "waiting for an URL doesn't have sense without an expected sender" ) if $opt_wait && $opt_url && !$opt_sender;
msgErr( "specifying an expected sender doesn't have sense if we do not wait for and URL" ) if $opt_wait && $opt_sender && !$opt_url;
msgErr( "specifying an expected sender or an URL doesn't have sense without waiting for them" ) if ( $opt_sender || $opt_url ) && !$opt_wait;

if( !TTP::errs()){
	doSwitchIP();
}

TTP::exit();
