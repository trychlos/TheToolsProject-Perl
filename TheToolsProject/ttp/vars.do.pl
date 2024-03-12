# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]siteRoot          display the site-defined root path [${siteRoot}]
# @(-) --[no]logsRoot          display the Toops logs Root (not daily) [${logsRoot}]
# @(-) --[no]logsDir           display the current Toops logs directory [${logsDir}]
# @(-) --[no]alertsDir         display the 'alerts' file directory [${alertsDir}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
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
	logsDir => 'no',
	alertsDir => 'no',
	key => ''
};

my $opt_siteRoot = false;
my $opt_logsDir = false;
my $opt_logsRoot = false;
my $opt_alertsDir = false;

# list of keys
my @keys = ();

# -------------------------------------------------------------------------------------------------
# list alertsDir value - e.g. 'C:\INLINGUA\Logs\240201\Alerts'
sub listAlertsdir {
	my $str = "alertsDir: ".Mods::Path::alertsDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
sub listByKeys {
	my $value = ttpVar( \@keys );
	print "  ".join( ',', @keys ).": $value".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsDir value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogsdir {
	my $str = "logsDir: ".Mods::Path::logsDailyDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsRoot value - e.g. 'C:\INLINGUA\Logs'
sub listLogsroot {
	my $str = "logsRoot: ".Mods::Path::logsRootDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list siteRoot value - e.g. 'C:\INLINGUA'
sub listSiteroot {
	my $str = "siteRoot: ".Mods::Path::siteRoot();
	msgVerbose( "returning '$str'" );
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
	"logsDir!"			=> \$opt_logsDir,
	"alertsDir!"		=> \$opt_alertsDir,
	"key=s@"			=> \$opt_key )){

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
msgVerbose( "found siteRoot='".( $opt_siteRoot ? 'true':'false' )."'" );
msgVerbose( "found logsRoot='".( $opt_logsRoot ? 'true':'false' )."'" );
msgVerbose( "found logsDir='".( $opt_logsDir ? 'true':'false' )."'" );
msgVerbose( "found alertsDir='".( $opt_alertsDir ? 'true':'false' )."'" );
@keys = split( /,/, join( ',', @{$opt_key} ));
msgVerbose( "found keys='".join( ',', @keys )."'" );

if( !ttpErrs()){
	listSiteroot() if $opt_siteRoot;
	listLogsroot() if $opt_logsRoot;
	listLogsdir() if $opt_logsDir;
	listAlertsdir() if $opt_alertsDir;
	listByKeys() if scalar @keys;
}

ttpExit();
