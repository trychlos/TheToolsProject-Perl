# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]services          list defined services [${services}]
# @(-) --[no]workloads         list used workloads [${workloads}]
# @(-) --workload=s            display the tasks for the named workload [${workload}]
# @(-) --[no]commands          display the commands for the named workload [${commands}]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Dbms;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	services => 'no',
	workloads => 'no',
	workload => '',
	commands => 'no'
};

my $opt_services = false;
my $opt_workloads = false;
my $opt_workload = $defaults->{workload};
my $opt_commands = false;

# -------------------------------------------------------------------------------------------------
# list the defined DBMS instances (which may be not all the running instances)
sub listDbms(){
	Mods::Services::listDefinedDBMSInstances();
}

# -------------------------------------------------------------------------------------------------
# list the defined services (same than ttp.pl list -services)
sub listServices(){
	Mods::Services::listDefinedServices();
}

# -------------------------------------------------------------------------------------------------
# list the workload tasks
sub listWorkloadAll(){
	Mods::Services::listWorkloadTasksAll( $opt_workload );
}

# -------------------------------------------------------------------------------------------------
# list the workload tasks commands
sub listWorkloadCommands(){
	Mods::Services::listWorkloadTasksCommands( $opt_workload );
}

# -------------------------------------------------------------------------------------------------
# list the defined workloads
sub listWorkloads(){
	Mods::Services::listUsedWorkloads();
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"services!"			=> \$opt_services,
	"workloads!"		=> \$opt_workloads, 
	"workload=s"		=> \$opt_workload,
	"commands!"			=> \$opt_commands )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found services='$opt_services'" );
Mods::Toops::msgVerbose( "found workloads='$opt_workloads'" );
Mods::Toops::msgVerbose( "found workload='$opt_workload'" );
Mods::Toops::msgVerbose( "found commands='$opt_commands'" );

if( !Mods::Toops::errs()){
	listDbms() if $opt_dbms;
	listServices() if $opt_services;
	listWorkloads() if $opt_workloads;
	listWorkloadAll() if $opt_workload && !$opt_commands;
	listWorkloadCommands() if $opt_workload && $opt_commands;
}

Mods::Toops::ttpExit();
