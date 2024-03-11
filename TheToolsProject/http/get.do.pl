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
use HTTP::Request;
use LWP::UserAgent;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );

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
	msgOut( "requesting '$opt_url'..." );
	my $ua = LWP::UserAgent->new();
	$ua->timeout( 5 );
	my $req = HTTP::Request->new( GET => $opt_url );
	my $response = $ua->request( $req );
	my $res = $response->is_success;
	msgVerbose( "receiving HTTP status='".$response->code."', success='".( $res ? 'true' : 'false' )."'" );
	if( $res ){
		msgLog( "content='".$response->decoded_content."'" );
	} else {
		msgLog( "status='".$response->status_line."'" );
		if( $opt_ignore ){
			msgVerbose( "erroneous HTTP status ignored as opt_ignore='true'" );
			$res = true;
		}
	}
	if( $opt_header ){
		my $header = $response->header( $opt_header );
		print "  $opt_header: $header".EOL;
	} else {
		print Dumper( $response );
	}
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
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
msgVerbose( "found url='$opt_url'" );
msgVerbose( "found header='$opt_header'" );
msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );

# url is mandatory
msgErr( "url is required, but is not specified" ) if !$opt_url;

if( !ttpErrs()){
	doGet() if $opt_url;
}

ttpExit();
