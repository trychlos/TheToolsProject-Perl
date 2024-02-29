# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]logsdir           display the current Toops logs directory [${logsdir}]
# @(-) --[no]logsroot          display the Toops logs Root (not daily) [${logsroot}]
# @(-) --[no]siteroot          display the site-defined root path [${siteroot}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Sys::Hostname qw( hostname );

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	logsdir => 'no',
	logsroot => 'no',
	siteroot => 'no'
};

my $opt_logsroot = false;
my $opt_logsdir = false;
my $opt_siteroot = false;

# -------------------------------------------------------------------------------------------------
# list logsroot value - e.g. 'C:\INLINGUA\Logs'
sub listLogsroot {
	my $str = "logsRoot: $TTPVars->{config}{toops}{logsRoot}";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsdir value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogsdir {
	my $str = "logsDir: $TTPVars->{config}{toops}{logsDir}";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteroot value - e.g. 'C:\INLINGUA'
sub listSiteroot {
	my $str = "siteRoot: $TTPVars->{config}{site}{rootDir}";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"logsdir!"			=> \$opt_logsdir,
	"logsroot!"			=> \$opt_logsroot,
	"siteroot!"			=> \$opt_siteroot )){

		Mods::Toops::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found logsdir='".( $opt_logsdir ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found logsroot='".( $opt_logsroot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found siteroot='".( $opt_siteroot ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listLogsdir() if $opt_logsdir;
	listLogsroot() if $opt_logsroot;
	listSiteroot() if $opt_siteroot;
}

Mods::Toops::ttpExit();
