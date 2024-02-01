# @(#) list various DBMS objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
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
	rc => 'rc',
	count => 0
};

my $opt_instance = $defaults->{instance};

# -------------------------------------------------------------------------------------------------
# list the databases
sub listDatabases {
	Mods::Dbms::listLiveDatabases();
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"instance=s"		=> \$opt_instance,
	"databases!"		=> \$opt_databases )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );

Mods::Services::checkServiceOpt( $opt_service, { mandatory => false });
Mods::Dbms::checkInstanceOpt( $opt_instance, { mandatory => false, single => false });

# we want either a service or an instance (and not both)
# if we have a service, setup the instance
if( !$TTPVars->{dbms}{service} && !$TTPVars->{dbms}{instance} ){
	Mods::Toops::msgErr( "one of '--service' or '--instance' options must be specified" );

} elsif( $TTPVars->{dbms}{service} && $TTPVars->{dbms}{instance} ){
	Mods::Toops::msgErr( "only one of '--service' or '--instance' optiosn must be specified" );

} elsif( $TTPVars->{dbms}{service} ){
	my $instance = $TTPVars->{dbms}{service}{data}{dbms};
	if( $instance ){
		Mods::Dbms::setInstanceByName( $instance );
	} else {
		Mods::Toops::msgWarn( "seems that the '$TTPVars->{dbms}{service}{name}' service doesn't have any 'dbms' information" );
	}
}

#print Dumper( $TTPVars->{$TTPVars->{run}{command}{name}} );

if( !Mods::Toops::errs()){
	listDatabases() if $opt_databases;
}

Mods::Toops::ttpExit();
