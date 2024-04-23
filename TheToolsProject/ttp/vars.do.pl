# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]nodeRoot          display the site-defined root path [${nodeRoot}]
# @(-) --[no]logsRoot          display the TTP logs root (not daily) [${logsRoot}]
# @(-) --[no]logsDaily         display the TTP daily root [${logsDaily}]
# @(-) --[no]logsCommands      display the current Toops logs directory [${logsCommands}]
# @(-) --[no]alertsDir         display the 'alerts' file directory [${alertsDir}]
# @(-) --key=<name[,...]>      the key which addresses the desired value, may be specified several times or as a comma-separated list [${key}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use TTP::Path;
use TTP::Services;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	nodeRoot => 'no',
	logsRoot => 'no',
	logsDaily => 'no',
	logsCommands => 'no',
	alertsDir => 'no',
	key => ''
};

my $opt_nodeRoot = false;
my $opt_logsCommands = false;
my $opt_logsRoot = false;
my $opt_logsDaily = false;
my $opt_alertsDir = false;

# list of keys
my @keys = ();

# -------------------------------------------------------------------------------------------------
# list alertsDir value - e.g. 'C:\INLINGUA\Logs\240201\Alerts'
sub listAlertsdir {
	my $str = "alertsDir: ".TTP::Path::alertsDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
sub listByKeys {
	my $value = ttpVar( \@keys );
	print "  ".join( ',', @keys ).": $value".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsDaily value - e.g. 'C:\INLINGUA\Logs\240201'
sub listLogsdaily {
	my $str = "logsDaily: ".TTP::logsDaily();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsCommands value - e.g. 'C:\INLINGUA\Logs\240201\Toops'
sub listLogscommands {
	my $str = "logsCommands: ".TTP::logsCommands();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsRoot value - e.g. 'C:\INLINGUA\Logs'
sub listLogsroot {
	my $str = "logsRoot: ".TTP::logsRoot();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list nodeRoot value - e.g. 'C:\INLINGUA'
sub listNoderoot {
	my $str = "nodeRoot: ".TTP::nodeRoot();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> $running->helpRef(),
	"verbose!"			=> $running->verboseRef(),
	"colored!"			=> $running->coloredRef(),
	"dummy!"			=> $running->dummyRef(),
	"nodeRoot!"			=> \$opt_nodeRoot,
	"logsRoot!"			=> \$opt_logsRoot,
	"logsDaily!"		=> \$opt_logsDaily,
	"logsCommands!"		=> \$opt_logsCommands,
	"alertsDir!"		=> \$opt_alertsDir,
	"key=s@"			=> \$opt_key )){

		msgOut( "try '".$running->runnableBasename()." ".$running->verbName()." --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::wantsHelp()){
	TTP::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found nodeRoot='".( $opt_nodeRoot ? 'true':'false' )."'" );
msgVerbose( "found logsRoot='".( $opt_logsRoot ? 'true':'false' )."'" );
msgVerbose( "found logsDaily='".( $opt_logsDaily ? 'true':'false' )."'" );
msgVerbose( "found logsCommands='".( $opt_logsCommands ? 'true':'false' )."'" );
msgVerbose( "found alertsDir='".( $opt_alertsDir ? 'true':'false' )."'" );
@keys = split( /,/, join( ',', @{$opt_key} ));
msgVerbose( "found keys='".join( ',', @keys )."'" );

if( !ttpErrs()){
	listAlertsdir() if $opt_alertsDir;
	listLogsdaily() if $opt_logsDaily;
	listLogscommands() if $opt_logsCommands;
	listLogsroot() if $opt_logsRoot;
	listNoderoot() if $opt_nodeRoot;
	listByKeys() if scalar @keys;
}

ttpExit();
