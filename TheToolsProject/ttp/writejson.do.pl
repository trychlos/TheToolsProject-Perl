# @(#) write JSON data into a file
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --file=<filename>       the filename where to write the data [${file}]
# @(-) --data=<data>           the data to be written as a JSON string [${data}]
# @(-) --[no]append            whether to append to the file [${append}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use JSON;

use Mods::Constants qw( :all );
use Mods::Message;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	file => '',
	data => '{}',
	append => 'no'
};

my $opt_file = $defaults->{file};
my $opt_data = $defaults->{data};
my $opt_append = false;

# -------------------------------------------------------------------------------------------------
# write the data into the file
sub doWriteJson {
	Mods::Message::msgOut( "writing JSON data into $opt_file..." );
	my @to = split( /,/, $opt_to );
	my $res = false;
	my $json = JSON->new;
	my $data = $json->decode( $opt_data );
	if( $opt_append ){
		$res = Mods::Toops::jsonAppend( $data, $opt_file );
	} else {
		$res = Mods::Toops::jsonWrite( $data, $opt_file );
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
	"file=s"			=> \$opt_file,
	"data=s"			=> \$opt_data,
	"append!"			=> \$opt_append )){

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
Mods::Message::msgVerbose( "found file='$opt_file'" );
Mods::Message::msgVerbose( "found data='$opt_data'" );
Mods::Message::msgVerbose( "found append='".( defined $opt_append ? ( $opt_append ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
Mods::Message::msgErr( "file is mandatory, not specified" ) if !$opt_file;
Mods::Message::msgErr( "data is mandatory, not specified" ) if !$opt_data;

if( !Mods::Toops::errs()){
	doWriteJson();
}

Mods::Toops::ttpExit();
