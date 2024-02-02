# @(#) list various TTP objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]commands          list the available commands [${commands}]
# @(-) --[no]services          list the defined services on this host [${services}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	commands => 'no',
	services => 'no'
};

my $opt_commands = false;
my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list the available commands (same than services.pl list -services)
sub listCommands {
	Mods::Toops::msgOut( "displaying available commands..." );
	my @commands = Mods::Toops::getAvailableCommands();
	foreach my $it ( @commands ){
		Mods::Toops::commandDisplayOneLineHelp( $it, { prefix => ' ' });
	}
	Mods::Toops::msgOut( scalar @commands." found command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the defined services
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying services defined on $hostConfig->{host}..." );
	my @list = Mods::Services::getDefinedServices( $hostConfig );
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @list." found defined service(s)" );
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
	Mods::Toops::doHelpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listCommands() if $opt_commands;
	listServices() if $opt_services;
}

Mods::Toops::ttpExit();
