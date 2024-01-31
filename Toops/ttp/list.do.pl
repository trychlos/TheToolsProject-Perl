# @(#) list various TTP objects
# Copyright (@) 2023-2024 PWI Consulting
#
# @(#) --help (managed by Toops)
# @(#) --verbose
# @(#) --services
# @(#) --dbms
# @(#) List defined objects
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
# list the defined services
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
