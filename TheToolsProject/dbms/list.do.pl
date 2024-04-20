# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]listdb            list the databases of the named instance [${listdb}]
# @(-) --database=<name>       acts on the named database [${database}]
# @(-) --[no]listtables        list the tables of the named database [${listtables}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Dbms;
use TTP::Message qw( :all );
use TTP::Services;

my $TTPVars = TTP::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
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
	my $hostConfig = TTP::Toops::getHostConfig();
	msgOut( "displaying databases in '$hostConfig->{name}\\$opt_instance'..." );
	my $list = TTP::Dbms::getLiveDatabases();
	foreach my $db ( @{$list} ){
		print " $db".EOL;
	}
	msgOut( scalar @{$list}." found live database(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the tables
sub listTables {
	my $hostConfig = TTP::Toops::getHostConfig();
	msgOut( "displaying tables in '$hostConfig->{name}\\$opt_instance\\$opt_database'..." );
	my $list = TTP::Dbms::getDatabaseTables( $opt_database );
	foreach my $it ( @{$list} ){
		print " $it".EOL;
	}
	msgOut( scalar @{$list}." found table(s)" );
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
	"listdb!"			=> \$opt_listdb,
	"database=s"		=> \$opt_database,
	"listtables!"		=> \$opt_listtables )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::Toops::wantsHelp()){
	TTP::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found instance='$opt_instance'" );
msgVerbose( "found listdb='".( $opt_listdb ? 'true':'false' )."'" );
msgVerbose( "found database='$opt_database'" );
msgVerbose( "found listtables='".( $opt_listtables ? 'true':'false' )."'" );

# instance is mandatory
TTP::Dbms::checkInstanceName( $opt_instance );

# check that the database exists if it is specified
TTP::Dbms::checkDatabaseExists( $opt_instance, $opt_database ) if $opt_instance && $opt_database;

if( !ttpErrs()){
	listDatabases() if $opt_listdb;
	listTables() if $opt_database && $opt_listtables;
}

ttpExit();
