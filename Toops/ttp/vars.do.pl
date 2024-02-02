# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]logsdir           display the current Toops logs directory [${logsdir}]
# @(-) --[no]siteroot          display the site-defined root path [${siteroot}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	logsdir => 'no',
	siteroot => 'no'
};

my $opt_logsdir = false;
my $opt_siteroot = false;

# -------------------------------------------------------------------------------------------------
# list logsdir value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogsdir {
	print " $TTPVars->{config}{site}{toops}{logsDir}".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteroot value - e.g. 'C:\INLINGUA'
sub listLogsroot {
	print " $TTPVars->{config}{site}{site}{rootDir}".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"logsdir!"			=> \$opt_logsdir,
	"siteroot!"			=> \$opt_siteroot )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found logsdir='".( $opt_logsdir ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found siteroot='".( $opt_siteroot ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listLogsdir() if $opt_logsdir;
	listLogsroot() if $opt_siteroot;
}

Mods::Toops::ttpExit();
