# @(#) display internal DBMS variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]backupsRoot       display the root (non daily) of the DBMS backup path [${backupsRoot}]
# @(-) --[no]backupsDir       display the root (non daily) of the DBMS backup path [${backupsDir}]
# @(-) --[no]archivesRoot      display the root (non daily) of the DBMS archive path [${archivesRoot}]
# @(-) --[no]archivesDir      display the root (non daily) of the DBMS archive path [${archivesDir}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use Mods::Path;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	backupsRoot => 'no',
	backupsDir => 'no',
	archivesRoot => 'no',
	archivesDir => 'no'
};

my $opt_backupsRoot = false;
my $opt_backupsDir = false;
my $opt_archivesRoot = false;
my $opt_archivesDir = false;

# -------------------------------------------------------------------------------------------------
# list archivesDir value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups\240101'
sub listArchivesdir {
	my $dir = Mods::Path::dbmsArchivesDir();
	my $str = "archivesDir: $dir";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list archivesRoot value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups'
sub listArchivesroot {
	my $dir = Mods::Path::dbmsArchivesRoot();
	my $str = "archivesRoot: $dir";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsDir value - e.g. 'C:\INLINGUA\SQLBackups\240101\WS12DEV1'
sub listBackupsdir {
	my $dir = Mods::Path::dbmsBackupsDir();
	my $str = "backupsDir: $dir";
	Mods::Toops::msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backupsRoot value - e.g. 'C:\INLINGUA\SQLBackups'
sub listBackupsroot {
	my $dir = Mods::Path::dbmsBackupsRoot();
	my $str = "backupsRoot: $dir";
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
	"backupsRoot!"		=> \$opt_backupsRoot,
	"backupsDir!"		=> \$opt_backupsDir,
	"archivesRoot!"		=> \$opt_archivesRoot,
	"archivesDir!"		=> \$opt_archivesDir )){

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
Mods::Toops::msgVerbose( "found backupsRoot='".( $opt_backupsRoot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found backupsDir='".( $opt_backupsDir ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found archivesRoot='".( $opt_archivesRoot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found archivesDir='".( $opt_archivesDir ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listArchivesroot() if $opt_archivesRoot;
	listArchivesdir() if $opt_archivesDir;
	listBackupsroot() if $opt_backupsRoot;
	listBackupsdir() if $opt_backupsDir;
}

Mods::Toops::ttpExit();
