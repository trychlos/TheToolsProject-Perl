# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]listdb            list the databases of the named instance [${listdb}]
# @(-) --database=<name>       acts on the named database [${database}]
# @(-) --[no]listtables        list the tables of the named database [${listtables}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use TTP::Dbms;
use TTP::Service;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
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
	my $hostConfig = TTP::getHostConfig();
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
	my $hostConfig = TTP::getHostConfig();
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
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"instance=s"		=> \$opt_instance,
	"listdb!"			=> \$opt_listdb,
	"database=s"		=> \$opt_database,
	"listtables!"		=> \$opt_listtables )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found instance='$opt_instance'" );
msgVerbose( "found listdb='".( $opt_listdb ? 'true':'false' )."'" );
msgVerbose( "found database='$opt_database'" );
msgVerbose( "found listtables='".( $opt_listtables ? 'true':'false' )."'" );

# instance is mandatory
TTP::Dbms::checkInstanceName( $opt_instance );

# check that the database exists if it is specified
TTP::Dbms::checkDatabaseExists( $opt_instance, $opt_database ) if $opt_instance && $opt_database;

if( !TTP::errs()){
	listDatabases() if $opt_listdb;
	listTables() if $opt_database && $opt_listtables;
}

TTP::exit();
