# @(#) display internal TTP variables
#
# @(-) --[no]help              print this message, and exit [${opt_help_def}]
# @(-) --[no]verbose           run verbosely [$opt_verbose_def]
# @(-) --[no]logsdir           display the current Toops logs directory path [$opt_logsdir_def]
# @(-) --[no]logsroot          display the site-defined logs root path [$opt_logsroot_def]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $opt_logsdir_def = 'no';
my $opt_logsdir = false;
my $opt_logsroot_def = 'no';
my $opt_logsroot = false;

# -------------------------------------------------------------------------------------------------
# list logsdir value - e.g. 'C:\INLINGUA\Logs\Toops\240201'
sub listLogsdir(){
	print " $TTPVars->{dyn}{logs_dir}".EOL;
}

# -------------------------------------------------------------------------------------------------
# list logsroot value - e.g. 'C:\INLINGUA\Logs\Toops'
sub listLogsroot(){
	print " $TTPVars->{config}{site}{toops}{logsRoot}".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"logsdir!"			=> \$opt_logsdir,
	"logsroot!"			=> \$opt_logsroot )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb();
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found logsdir='$opt_logsdir'" );
Mods::Toops::msgVerbose( "found logsroot='$opt_logsroot'" );

if( !Mods::Toops::errs()){
	listLogsdir() if $opt_logsdir;
	listLogsroot() if $opt_logsroot;
}

Mods::Toops::ttpExit();
