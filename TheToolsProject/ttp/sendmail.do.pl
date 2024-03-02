# @(#) send an email using the configured SMTP gateway
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --subject=<subject>     the email subject [${subject}]
# @(-) --text=<text>           the text body [${text}]
# @(-) --textfname=<filename>  the filename which contains the text body [${textfname}]
# @(-) --html=<html>           the HTML body [${html}]
# @(-) --htmlfname=<filename>  the filename which contains the HTML body [${htmlfname}]
# @(-) --to=<to>               a comma-separated list of target email addresses [${to}]
# @(-) --[no]debug             debug the SMTP transport phase [${debug}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Path::Tiny;

use Mods::Constants qw( :all );
use Mods::Mail;
use Mods::Message;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	subject => '',
	text => '',
	textfname => '',
	html => '',
	htmlfname => '',
	to => '',
	debug => 'no'
};

my $opt_subject = $defaults->{subject};
my $opt_text = $defaults->{text};
my $opt_textfname = $defaults->{textfname};
my $opt_html = $defaults->{html};
my $opt_htmlfname = $defaults->{htmlfname};
my $opt_to = $defaults->{to};
my $opt_debug = undef;

# -------------------------------------------------------------------------------------------------
# send the email
sub doSendmail {
	Mods::Message::msgOut( "sending an email to $opt_to..." );
	my @to = split( /,/, $opt_to );
	my $text = undef;
	$text = $opt_text if $opt_text;
	if( $opt_textfname ){
		my $fh = path( $opt_textfname );
		$text = $fh->slurp_utf8;
	}
	my $html = undef;
	$html = $opt_html if $opt_html;
	if( $opt_htmlfname ){
		my $fh = path( $opt_htmlfname );
		$html = $fh->slurp_utf8;
	}
	my $res = Mods::Mail::send({
		subject => $opt_subject,
		text => $text,
		html => $shtml,
		to => \@to,
		debug => $opt_debug
	});
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
	"subject=s"			=> \$opt_subject,
	"text=s"			=> \$opt_text,
	"textfname=s"		=> \$opt_textfname,
	"html=s"			=> \$opt_html,
	"htmlfname=s"		=> \$opt_htmlfname,
	"to=s"				=> \$opt_to,
	"debug!"			=> \$opt_debug )){

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
Mods::Message::msgVerbose( "found subject='$opt_subject'" );
Mods::Message::msgVerbose( "found text='$opt_text'" );
Mods::Message::msgVerbose( "found textfname='$opt_textfname'" );
Mods::Message::msgVerbose( "found html='$opt_html'" );
Mods::Message::msgVerbose( "found htmlfname='$opt_htmlfname'" );
Mods::Message::msgVerbose( "found to='$opt_to'" );
Mods::Message::msgVerbose( "found debug='".( defined $opt_debug ? ( $opt_debug ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
Mods::Message::msgErr( "subject is empty, but shouldn't" ) if !$opt_subject;
Mods::Message::msgErr( "content is empty, but shouldn't" ) if !$opt_text && !$opt_textfname && !$opt_html && !$opt_htmlfname;
Mods::Message::msgErr( "target is empty, but shouldn't" ) if !$opt_to;

# text and textfname are mutually exclusive, so are html and htmlfname
Mods::Message::msgErr( "text body can only provided one way, but both '--text' and '--textfname' are specified" ) if $opt_text && $opt_textfname;
Mods::Message::msgErr( "HTML body can only provided one way, but both '--html' and '--htmlfname' are specified" ) if $opt_html && $opt_htmlfname;

if( !Mods::Toops::errs()){
	doSendmail();
}

Mods::Toops::ttpExit();
