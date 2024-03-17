# @(#) run a GET on a HTTP endpoint
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --url=<url>             the URL to be requested [${url}]
# @(-) --header=<header>       output the received (case insensitive) header [${header}]
# @(-) --[no]ignore            ignore HTTP status as soon as we receive something from the server [${ignore}]
# @(-) --[no]response          print the received response to stdout [${response}]
# @(-) --[no]mqtt              publish MQTT telemetry [${mqtt}]
# @(-) --[no]http              publish HTTP telemetry [${http}]
# @(-) --label=<name=value>    label to be added to the telemetry, may be specified several times or as a comma-separated list [${label}]
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
	response => 'no',
	ignore => 'no',
	mqtt => 'no',
	http => 'no',
	label => ''
};

my $opt_url = $defaults->{url};
my $opt_header = $defaults->{header};
my $opt_response = false;
my $opt_ignore = false;
my $opt_mqtt = false;
my $opt_http = false;
my $opt_label = $defaults->{label};

# list of labels
my @labels = ();

# a list of not-ignored status
# 500 Can't connect to ip.test.blingua.net:443 (Connection timed out)
# 500 Can't connect to ip2.test.blingua.net:80 (No such host is known)
my @notIgnored = (
	'Connection timed out',
	'No such host is known',
	'Name or service not known'
);

# -------------------------------------------------------------------------------------------------
# request the url
sub doGet {
	msgOut( "requesting '$opt_url'..." );
	my $ua = LWP::UserAgent->new();
	$ua->timeout( 5 );
	my $req = HTTP::Request->new( GET => $opt_url );
	my $response = $ua->request( $req );
	my $res = $response->is_success;
	my $status = $response->code;
	msgVerbose( "receiving HTTP status='$status', success='".( $res ? 'true' : 'false' )."'" );
	if( $res ){
		msgLog( "content='".$response->decoded_content."'" );
	} else {
		$status = $response->status_line;
		msgLog( "status='$status'" );
		if( $opt_ignore && _isIgnored( $status )){
			msgVerbose( "erroneous HTTP status ignored as opt_ignore='true'" );
			$res = true;
		}
	}

	# and send the telemetry if opt-ed in
	my ( $proto, $path ) = split( /:\/\//, $opt_url );
	my $value = $res ? "1" : "0";
	my $other_labels = "";
	foreach my $it ( @labels ){
		$other_labels .= " -label $it";
	}
	$other_labels .= " -label proto=$proto";
	$other_labels .= " -label path=$path";
	msgVerbose( "added labels '$labels'" );
	if( $opt_mqtt ){
		# topic is HOST/telemetry/service/SERVICE/proto/PROTO/path/PATH/url_status
		$command = "telemetry.pl publish -metric url_status $other_labels -value=$value -mqtt -nohttp";
		`$command`;
	}
	if( $opt_http ){
		# send the full url as a label
		$command = "telemetry.pl publish -metric ttp_url_status -label url=$opt_url $other_labels -value=$value -nomqtt -http";
		`$command`;
	}

	if( $res ){
		if( $opt_header ){
			my $header = $response->header( $opt_header );
			print "  $opt_header: $header".EOL;
		}
		if( $opt_response ){
			print Dumper( $response );
		}
		msgOut( "success" );
	} else {
		msgLog( Dumper( $response ));
		msgErr( "NOT OK: $status" );
	}
}

# -------------------------------------------------------------------------------------------------
# whether a status must return an error
# (I):
# - status
# (O):
# - returns true|false
sub _isIgnored {
	my ( $status ) = @_;
	my $ignored = true;
	foreach my $it ( @notIgnored ){
		$ignored = false if $status =~ m/$it/;
	}
	return $ignored;
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
	"response!"			=> \$opt_response,
	"ignore!"			=> \$opt_ignore,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"label=s@"			=> \$opt_label )){

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
msgVerbose( "found response='".( $opt_response ? 'true':'false' )."'" );
msgVerbose( "found ignore='".( $opt_ignore ? 'true':'false' )."'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
@labels = split( /,/, join( ',', @{$opt_label} ));
msgVerbose( "found labels='".join( ',', @labels )."'" );

# url is mandatory
msgErr( "url is required, but is not specified" ) if !$opt_url;

if( !ttpErrs()){
	doGet() if $opt_url;
}

ttpExit();
