# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${opt_help_def}]
# @(-) --[no]verbose           run verbosely [$opt_verbose_def]
# @(-) --[no]services          list defined services [$opt_services_def]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Dbms;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $opt_services_def = 'no';
my $opt_services = false;
my $opt_dbms_def = 'no';
my $opt_dbms = false;

# -------------------------------------------------------------------------------------------------
# list the defined services (same than ttp.pl list -services)
sub listServices(){
	Mods::Services::listDefinedServices();
}

# -------------------------------------------------------------------------------------------------
# list the defined DBMS instances (which may be not all the running instances)
sub listDbms(){
	Mods::Services::listDefinedDBMSInstances();
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"services!"			=> \$opt_services,
	"dbms!"				=> \$opt_dbms	)){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb();
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );

if( !Mods::Toops::errs()){
	listServices() if $opt_services;
	listDbms() if $opt_dbms;
}

Mods::Toops::ttpExit();
