# @(#) List available configurations
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]json              display available JSON configuration files [${json}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;
use Proc::Background;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	json => 'no'
};

my $opt_json = false;

# -------------------------------------------------------------------------------------------------
# display available JSON configuration files
sub doListJSON {
	msgOut( "displaying available JSON configuration files..." );
	my $json_path = TTP::Path::daemonsConfigurationsDir();
	opendir( my $dh, $json_path ) or msgErr( "opendir $json_path: $!" );
	if( !TTP::errs()){
		my $count = 0;
		my $sufixed_path = TTP::Path::withTrailingSeparator( $json_path );
		while( readdir( $dh )){
			if( $_ ne '.' && $_ ne '..' ){
				my $json = File::Spec->catpath( $sufixed_path, $_ );
				print "  $json".EOL;
				$count += 1;
			}
		}
		closedir( $dh );
		msgOut( "found $count JSON configuration files" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"verbose!"			=> \$ttp->{run}{verbose},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"json!"				=> \$opt_json )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );

msgWarn( "no action as '--json' option is not set" ) if !$opt_json;

if( !TTP::errs()){
	doListJSON() if $opt_json;
}

TTP::exit();
