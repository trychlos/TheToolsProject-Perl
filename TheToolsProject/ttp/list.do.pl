# @(#) list various TTP objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
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
	colored => 'no',
	dummy => 'no',
	commands => 'no',
	services => 'no'
};

my $opt_commands = false;
my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list the available commands (same than services.pl list -services)
sub listCommands {
	Mods::Message::msgOut( "displaying available commands..." );
	my @commands = Mods::Toops::getAvailableCommands();
	foreach my $it ( @commands ){
		Mods::Toops::helpCommandOneline( $it, { prefix => ' ' });
	}
	Mods::Message::msgOut( scalar @commands." found command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the defined services
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Message::msgOut( "displaying services defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedServices( $hostConfig );
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Message::msgOut( scalar @list." found defined service(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"commands!"			=> \$opt_commands,
	"services!"			=> \$opt_services )){

		Mods::Message::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Message::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listCommands() if $opt_commands;
	listServices() if $opt_services;
}

Mods::Toops::ttpExit();
