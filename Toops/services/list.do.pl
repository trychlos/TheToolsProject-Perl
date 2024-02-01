# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${opt_help_def}]
# @(-) --[no]verbose           run verbosely [$opt_verbose_def]
# @(-) --[no]services          list defined services [$opt_services_def]
# @(-) --[no]workloads         list used workloads [$opt_workloads_def]
# @(-) --workload=s            display the tasks for the named workload [$opt_workload_def]
# @(@) Remind that specifying -workload without any argument means the boolean option, while -workload my-workload means the string option.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Dbms;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $opt_services_def = 'no';
my $opt_services = false;
my $opt_workloads_def = 'no';
my $opt_workloads = false;
my $opt_workload_def = '';
my $opt_workload = $opt_workload_def;

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
sub listWorkload(){
	Mods::Services::listWorkloadTasks( $opt_workload );
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
	"workload=s"		=> \$opt_workload )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb();
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found services='$opt_services'" );
Mods::Toops::msgVerbose( "found workloads='$opt_workloads'" );
Mods::Toops::msgVerbose( "found workload='$opt_workload'" );

if( !Mods::Toops::errs()){
	listDbms() if $opt_dbms;
	listServices() if $opt_services;
	listWorkloads() if $opt_workloads;
	listWorkload() if $opt_workload;
}

Mods::Toops::ttpExit();
