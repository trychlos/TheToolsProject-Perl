# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]listdb            list the databases of the named instance [${listdb}]
# @(-) --database=<name>       acts on the named database [${database}]
# @(-) --[no]listtables        list the tables of the named database [${listtables}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Dbms;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	instance => 'MSSQLSERVER',
	listdb => 'no',
	database => '',
	listtables => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_listdb = false;
my $opt_database = $defaults->{database};
my $opt_listtables = false;

# -------------------------------------------------------------------------------------------------
# list the databases
sub listDatabases {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying databases in '$hostConfig->{name}\\$opt_instance'..." );
	my $list = Mods::Dbms::getLiveDatabases();
	foreach my $db ( @{$list} ){
		print " $db".EOL;
	}
	Mods::Toops::msgOut( scalar @{$list}." found live database(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the tables
sub listTables {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying tables in '$hostConfig->{name}\\$opt_instance\\$opt_database'..." );
	my $list = Mods::Dbms::getDatabaseTables( $opt_database );
	foreach my $it ( @{$list} ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @{$list}." found table(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"instance=s"		=> \$opt_instance,
	"listdb!"			=> \$opt_listdb,
	"database=s"		=> \$opt_database,
	"listtables!"		=> \$opt_listtables )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found listdb='".( $opt_listdb ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found listtables='".( $opt_listtables ? 'true':'false' )."'" );

# instance is mandatory
Mods::Dbms::checkInstanceOpt( $opt_instance );

# check that the database exists if it is specified
Mods::Dbms::checkDatabaseExists( $opt_instance, $opt_database ) if $opt_instance && $opt_database;

if( !Mods::Toops::errs()){
	listDatabases() if $opt_listdb;
	listTables() if $opt_database && $opt_listtables;
}

Mods::Toops::ttpExit();
