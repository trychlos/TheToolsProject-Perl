# @(#) publish all tables size from all databases on defined instances
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --limit=<limit>         limit the published messages [${limit}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Dbms;
use Mods::Metrology;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	limit => -1
};

my $opt_limit = $defaults->{limit};

# -------------------------------------------------------------------------------------------------
# publish all databases sizes for all defined instances on this host
sub doTablesCount {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "publishing databases size on $hostConfig->{name}..." );
	my $count = 0;
	my $instances = Mods::Toops::ttpFilter( `services.pl list -dbms` );
	if( scalar @{$instances} ){
		foreach my $instance ( @{$instances} ){
			last if $count >= $opt_limit && $opt_limit >= 0;
			Mods::Dbms::checkInstanceOpt( $instance );
			my $databases = Mods::Toops::ttpFilter( `dbms.pl list -instance $instance -listdb` );
			foreach my $db ( @{$databases} ){
				last if $count >= $opt_limit && $opt_limit >= 0;
				my $tables = Mods::Toops::ttpFilter( `dbms.pl list -instance $instance -database $db -listtables` );
				foreach my $tab ( @{$tables} ){
					last if $count >= $opt_limit && $opt_limit >= 0;
					my $sql = "use $db; select count(*) as rows_count from $tab";
					my $out = Mods::Toops::ttpFilter( `dbms.pl sql -instance $instance -command \"$sql\"` );
					my @resultSet = ();
					foreach my $line ( @{$out} ){
						next if $line =~ /Changed database context/;
						next if $line =~ /rows affected/;
						push( @resultSet, $line );
					}
					my $set = Mods::Metrology::interpretResultSet( @resultSet );
					$count += Mods::Metrology::publish( "dbms/$instance/database/$db/table/$tab", $set );
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
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"limit=i"			=> \$opt_limit )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	doTablesCount();
}

Mods::Toops::ttpExit();
