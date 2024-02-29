# @(#) restore a database
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       target database name [${database}]
# @(-) --full=<filename>       restore from this full backup [${full}]
# @(-) --diff=<filename>       restore with this differential backup [${diff}]
# @(-) --[no]verifyonly        only check the backup restorability [${verifyonly}]
#
# @(@) You must at least provide a full backup to restore, and may also provide an additional differential backup file.
# @(@) Target database is mandatory unless you just want a backup restorability check, in which case '--dummy' option is not honored.
#
# Copyright (@) 2023-2024 PWI Consulting

use Mods::Dbms;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	instance => 'MSSQLSERVER',
	database => '',
	full => '',
	diff => '',
	verifyonly => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_database = $defaults->{database};
my $opt_full = $defaults->{full};
my $opt_diff = $defaults->{diff};
my $opt_verifyonly = false;

my $fname = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file
sub doRestore {
	my $hostConfig = Mods::Toops::getHostConfig();
	if( $opt_verifyonly ){
		Mods::Toops::msgOut( "verifying the restorability of '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	} else {
		Mods::Toops::msgOut( "restoring database '$hostConfig->{name}\\$opt_instance\\$opt_database' from '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	}
	my $res = Mods::Dbms::restoreDatabase({
		instance => $opt_instance,
		database => $opt_database,
		full => $opt_full,
		diff => $opt_diff,
		verifyonly => $opt_verifyonly
	});
	if( !$opt_verifyonly ){
		my $mode = $opt_diff ? 'diff' : 'full';
		Mods::Toops::execReportByCommand({
			instance => $opt_instance,
			database => $opt_database,
			full => $opt_full,
			diff => $opt_diff || '',
			mode => $mode
		}, {
			topic => [ 'instance', 'database', 'mode' ],
			retain => true
		});
	}
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
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full=s"			=> \$opt_full,
	"diff=s"			=> \$opt_diff,
	"verifyonly!"		=> \$opt_verifyonly )){

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
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found full='$opt_full'" );
Mods::Toops::msgVerbose( "found diff='$opt_diff'" );
Mods::Toops::msgVerbose( "found verifyonly='".( $opt_verifyonly ? 'true':'false' )."'" );

my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

Mods::Toops::msgErr( "'--database' option is mandatory, but is not specified" ) if !$opt_database && !$opt_verifyonly;
Mods::Toops::msgErr( "'--full' option is mandatory, but is not specified" ) if !$opt_full;
Mods::Toops::msgErr( "$opt_diff: file not found or not readable" ) if $opt_diff && ! -f $opt_diff;

if( !Mods::Toops::errs()){
	doRestore();
}

Mods::Toops::ttpExit();
