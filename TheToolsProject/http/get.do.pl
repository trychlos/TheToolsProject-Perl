# @(#) run a GET on a HTTP endpoint
#
# @(-) --[no]help                  print this message, and exit [${help}]
# @(-) --[no]verbose               run verbosely [${verbose}]
# @(-) --[no]colored               color the output depending of the message level [${colored}]
# @(-) --[no]dummy                 dummy run (ignored here) [${dummy}]
# @(-) --url=<url>                 the URL to be requested [${url}]
# @(-) --header=<header>           output the received (case insensitive) header [${header}]
# @(-) --[no]ignore                ignore HTTP status as soon as we receive something from the server [${ignore}]
#
# @(@) Unless otherwise specified, default is to dump the site answer to stdout.
#
# Among other uses, this verb is notably used to check which machine answers to a given URL in an architecture which wants take advantage of IP Failover system.
# But, in such a system, all physical hosts hold the FO IP, and will answer to this IP is the request originates from the same physical host.
# To get accurate result, this verb must so be run from outside of the involved physical hosts.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use LWP::UserAgent;

use Mods::Constants qw( :all );
use Mods::Message;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	url => '',
	header => '',
	ignore => 'no'
};

my $opt_url = $defaults->{url};
my $opt_header = $defaults->{header};
my $opt_ignore = false;

# -------------------------------------------------------------------------------------------------
# request the url
sub doGet {
	Mods::Message::msgOut( "requesting '$opt_url'..." );
	my $ua = LWP::UserAgent->new();
	my $response = $ua->get( $opt_url );
	my $res = false;
	if( $opt_ignore ){
		Mods::Message::msgVerbose( "receiving HTTP status=$response->code, ignored as opt_ignore='true'" );
		$res = true;
	} else {
		$res = $response->is_success;
		Mods::Message::msgLog( $response );
	}
	if( $opt_header ){
		my $header = $response->header( $opt_header );
		Mods::Message::msgOut( "got $opt_header='$header'" );
	} else {
		print Dumper( $response );
	}
	if( $res ){
		Mods::Message::msgOut( "success" );
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
	"url=s"				=> \$opt_url,
	"header=s"			=> \$opt_header,
	"ignore!"			=> \$opt_ignore	)){

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
Mods::Message::msgVerbose( "found url='$opt_url'" );
Mods::Message::msgVerbose( "found header='$opt_header'" );
Mods::Message::msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );

# url is mandatory
Mods::Message::msgErr( "url is required, but is not specified" ) if !$opt_url;

if( !Mods::Toops::errs()){
	doGet() if $opt_url;
}

Mods::Toops::ttpExit();