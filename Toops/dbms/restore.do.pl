# @(#) restore a database
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       target database name [${database}]
# @(-) --full=<filename>       restore from this full backup [${full}]
# @(-) --diff=<filename>       restore with this differential backup [${diff}]
# @(-) --[no]check             only check the backup restorability [${check}]
#
# @(@) You must at least provide a full backup to restore, and may also provide an additional differential backup file.
#
# Copyright (@) 2023-2024 PWI Consulting

use Mods::Dbms;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	instance => 'MSSQLSERVER',
	database => '',
	full => '',
	diff => '',
	check => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_database = $defaults->{database};
my $opt_full = $defaults->{full};
my $opt_diff = $defaults->{diff};
my $opt_check = false;

my $fname = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file
sub doRestore {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "restoring database '$hostConfig->{host}\\$opt_instance\\$opt_database' from '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	my $res = Mods::Dbms::restoreDatabase({
		instance => $opt_instance,
		database => $opt_database,
		full => $opt_full,
		diff => $opt_diff,
		checkonly => $opt_check
	});
	if( $res ){
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full=s"			=> \$opt_full,
	"diff=s"			=> \$opt_diff,
	"check!"			=> \$opt_check )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found full='$opt_full'" );
Mods::Toops::msgVerbose( "found diff='$opt_diff'" );
Mods::Toops::msgVerbose( "found check='".( $opt_check ? 'true':'false' )."'" );

my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

Mods::Toops::msgErr( "'--database' option is mandatory, but is not specified" ) if !$opt_database;
Mods::Toops::msgErr( "'--full' option is mandatory, but is not specified" ) if !$opt_full;
Mods::Toops::msgErr( "$opt_diff: file not found or not readable" ) if $opt_diff && ! -f $opt_diff;

if( !Mods::Toops::errs()){
	doRestore();
}

Mods::Toops::ttpExit();
