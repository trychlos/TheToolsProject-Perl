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

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $TTPVars = TTP::TTPVars();

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
	msgOut( "writing JSON data into $opt_file..." );
	my @to = split( /,/, $opt_to );
	my $res = false;
	my $json = JSON->new;
	my $data = $json->decode( $opt_data );
	if( $opt_append ){
		$res = TTP::jsonAppend( $data, $opt_file );
	} else {
		$res = TTP::jsonWrite( $data, $opt_file );
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
	"file=s"			=> \$opt_file,
	"data=s"			=> \$opt_data,
	"append!"			=> \$opt_append )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::wantsHelp()){
	TTP::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found file='$opt_file'" );
msgVerbose( "found data='$opt_data'" );
msgVerbose( "found append='".( defined $opt_append ? ( $opt_append ? 'true':'false' ) : '(undef)' )."'" );

# all data are mandatory, and we must provide some content, either text or html
msgErr( "file is mandatory, not specified" ) if !$opt_file;
msgErr( "data is mandatory, not specified" ) if !$opt_data;

if( !ttpErrs()){
	doWriteJson();
}

ttpExit();
