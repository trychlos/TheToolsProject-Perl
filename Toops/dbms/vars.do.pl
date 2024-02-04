# @(#) display internal DBMS variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]backuproot        display the root (non daily) of the DBMS backup path [${backuproot}]
# @(-) --[no]archiveroot       display the root (non daily) of the DBMS archive path [${archiveroot}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	backuproot => 'no',
	archiveroot => 'no'
};

my $opt_backuproot = false;
my $opt_archiveroot = false;

# -------------------------------------------------------------------------------------------------
# list archiveroot value - e.g. '\\ftpback-rbx7-618.ovh.net\ns3153065.ip-51-91-25.eu\WS12DEV1\SQLBackups'
sub listArchiveroot {
	my $archivePath = Mods::Toops::pathFromCommand( "ttp.pl vars -archivePath" );
	my $hostConfig = Mods::Toops::getHostConfig();
	my ( $volume, $directories, $file ) = File::Spec->splitdir( $hostConfig->{backupRoot} );
	my $archiveRoot = File::Spec->catdir( $archivePath, $file );
	print " archiveRoot: $archiveRoot".EOL;
}

# -------------------------------------------------------------------------------------------------
# list backuproot value - e.g. 'C:\INLINGUA\SQLBackups'
sub listBackuproot {
	my $hostConfig = Mods::Toops::getHostConfig();
	print " backupRoot: $hostConfig->{backupRoot}".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"backuproot!"		=> \$opt_backuproot,
	"archiveroot!"		=> \$opt_archiveroot )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found backuproot='".( $opt_backuproot ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found archiveroot='".( $opt_archiveroot ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listArchiveroot() if $opt_archiveroot;
	listBackuproot() if $opt_backuproot;
}

Mods::Toops::ttpExit();
