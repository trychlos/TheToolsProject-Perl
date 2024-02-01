# @(#) list various TTP objects
#
# @(-) --[no]help              print this message, and exit [${opt_help_def}]
# @(-) --[no]verbose           run verbosely [$opt_verbose_def]
# @(-) --[no]commands          list the available commands [$opt_commands_def]
# @(-) --[no]services          list the defined services on this host [$opt_services_def]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $opt_commands_def = 'no';
my $opt_commands = false;
my $opt_services_def = 'no';
my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list the available commands (same than services.pl list -services)
sub listCommands(){
	Mods::Toops::listAvailableCommands();
}

# -------------------------------------------------------------------------------------------------
# list the defined services
sub listServices(){
	Mods::Services::listDefinedServices();
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"commands!"			=> \$opt_commands,
	"services!"			=> \$opt_services )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb();
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found commands='$opt_commands'" );
Mods::Toops::msgVerbose( "found services='$opt_services'" );

if( !Mods::Toops::errs()){
	listCommands() if $opt_commands;
	listServices() if $opt_services;
}

Mods::Toops::ttpExit();
