# @(#) publish all databases size on defined instances
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Dbms;
use Mods::Metrology;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no'
};

# -------------------------------------------------------------------------------------------------
# publish all databases sizes for all defined instances on this host
sub doDbSize {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "publishing databases size on $hostConfig->{name}..." );
	my $count = 0;
	my $instances = Mods::Toops::ttpFilter( `services.pl list -dbms` );
	if( scalar @{$instances} ){
		foreach my $instance ( @{$instances} ){
			Mods::Dbms::checkInstanceOpt( $instance );
			my $databases = Mods::Toops::ttpFilter( `dbms.pl list -instance $instance -listdb` );
			foreach my $db ( @{$databases} ){
				# sp_spaceused provides two results sets, where each one only contains one data row
				my $sql = "use $db; exec sp_spaceused";
				my $out = Mods::Toops::ttpFilter( `dbms.pl sql -instance $instance -command \"$sql\"` );
				my @resultSet = ();
				foreach my $line ( @{$out} ){
					# skip the first line 'Changed database context to ...' due to the 'use <database>'
					next if $line =~ /Changed database context/;
					#print $line.EOL;
					push( @resultSet, $line );
					if( scalar @resultSet == 3 ){
						my $set = Mods::Metrology::interpretResultSet( @resultSet );
						$count += Mods::Metrology::publish( "dbms/$instance/database/$db/dbsize", $set );
					}
				}
			}
		}
	} else {
		Mods::Toops::msgOut( "no DBMS instance defined on $host" );
	}
	Mods::Toops::msgOut( "$count published message(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose} )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	doDbSize();
}

Mods::Toops::ttpExit();
