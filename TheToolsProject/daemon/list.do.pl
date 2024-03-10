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

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Path;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

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
	my $json_path = Mods::Path::daemonsConfigurationsDir();
	opendir( my $dh, $json_path ) or msgErr( "opendir $json_path: $!" );
	if( !Mods::Toops::errs()){
		my $count = 0;
		my $sufixed_path = Mods::Path::withTrailingSeparator( $json_path );
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
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"json!"				=> \$opt_json )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );

msgWarn( "no action as '--json' option is not set" ) if !$opt_json;

if( !Mods::Toops::errs()){
	doListJSON() if $opt_json;
}

Mods::Toops::ttpExit();
