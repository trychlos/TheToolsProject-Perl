# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]siteRoot          display the site-defined root path [${siteRoot}]
# @(-) --[no]logsRoot          display the Toops logs Root (not daily) [${logsRoot}]
# @(-) --[no]logsDir           display the current Toops logs directory [${logsDir}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	siteRoot => 'no',
	logsRoot => 'no',
	logsDir => 'no'
};

my $opt_siteRoot = false;
my $opt_logsDir = false;
my $opt_logsRoot = false;

# -------------------------------------------------------------------------------------------------
# list logsDir value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogsdir {
	my $str = "logsDir: ".Mods::Path::logsDailyDir();
	Mods::Message::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsRoot value - e.g. 'C:\INLINGUA\Logs'
sub listLogsroot {
	my $str = "logsRoot: ".Mods::Path::logsRootDir();
	Mods::Message::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteRoot value - e.g. 'C:\INLINGUA'
sub listSiteroot {
	my $str = "siteRoot: $TTPVars->{config}{site}{rootDir}";
	Mods::Message::msgVerbose( "returning '$str'" );
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
	"siteRoot!"			=> \$opt_siteRoot,
	"logsRoot!"			=> \$opt_logsRoot,
	"logsDir!"			=> \$opt_logsDir )){

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
Mods::Message::msgVerbose( "found siteRoot='".( $opt_siteRoot ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found logsRoot='".( $opt_logsRoot ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found logsDir='".( $opt_logsDir ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listSiteroot() if $opt_siteRoot;
	listLogsroot() if $opt_logsRoot;
	listLogsdir() if $opt_logsDir;
}

Mods::Toops::ttpExit();
