# @(#) get and publish some databases metrology data
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --service=<name>        service name [${service}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]dbsize            get databases size for the specified instance [${dbsize}]
# @(-) --[no]tabcount          get tables rows count for the specified database [${tabcount}]
# @(-) --limit=<limit>         limit the published messages [${limit}]
#
# @(@) When limiting the published messages, be conscious that the '--dbsize' option provides 7 messages per database.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Dbms;
use Mods::Metrology;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	service => '',
	instance => 'MSSQLSERVER',
	database => '',
	dbsize => 'no',
	tabcount => 'no',
	limit => -1
};

my $opt_service = $defaults->{service};
my $opt_instance = '';
my $opt_database = $defaults->{database};
my $opt_dbsize = false;
my $opt_tabcout = false;
my $opt_limit = $defaults->{limit};

# this host configuration
my $hostConfig = Mods::Toops::getHostConfig();

# list of databases to be measured (or none, depending of the option)
my @databases = ();

# note that the sp_spaceused stored procedure returns:
# - TWO resuts sets
# - and that units are in the data: we move them to the column names
# below a sample of the got result
=pod
Changed database context to 'Canal33'.
database_name                                                                                                                    database_size      unallocated space 
-------------------------------------------------------------------------------------------------------------------------------- ------------------ ------------------
Canal33                                                                                                                          18746.06 MB        0.67 MB           
reserved           data               index_size         unused            
------------------ ------------------ ------------------ ------------------
19191824 KB        12965152 KB        6182104 KB         44568 KB          
=cut

# -------------------------------------------------------------------------------------------------
# modify the result set to move the units to the column names
# remove the database_name from the published result
sub _modifySet {
	my ( $set ) = @_;
	my @res = ();
	foreach my $row ( @{$set} ){
		my $it = {};
		foreach my $key ( keys %{$row} ){
			# unchanged keys
			if( $key eq "database_name" ){
				#$it->{$key} = $row->{$key};
				next;
			} else {
				my $data = $row->{$key};
				my @words = split( /\s+/, $data );
				$it->{$key.'_'.$words[1]} = $words[0];
			}
		}
		push( @res, $it );
	}
	return \@res;
}

# -------------------------------------------------------------------------------------------------
# publish all databases sizes for the specified instance
# if a service has been specified, only consider the databases of this service
# if only an instance has been specified, then search for all databases of this instance
# at the moment, a service is stucked to a single instance
sub doDbSize {
	Mods::Toops::msgOut( "publishing databases size on '$hostConfig->{name}\\$opt_instance'..." );
	my $count = 0;
	my $list = [];
	if( $opt_service ){
		$list = \@databases;
	} elsif( !$opt_database ){
		$list = Mods::Toops::ttpFilter( `dbms.pl list -instance $opt_instance -listdb` );
	} else {
		push( @{$list}, $opt_database );
	}
	foreach my $db ( @{$list} ){
		last if $count >= $opt_limit && $opt_limit >= 0;
		# sp_spaceused provides two results sets, where each one only contains one data row
		my $sql = "use $db; exec sp_spaceused";
		my $out = Mods::Toops::ttpFilter( `dbms.pl sql -instance $opt_instance -command \"$sql\"` );
		my @resultSet = ();
		foreach my $line ( @{$out} ){
			# skip the first line 'Changed database context to ...' due to the 'use <database>'
			next if $line =~ /Changed database context/;
			#print $line.EOL;
			push( @resultSet, $line );
			if( scalar @resultSet == 3 ){
				my $set = Mods::Metrology::interpretResultSet( @resultSet );
				$set = _modifySet( $set );
				$count += Mods::Metrology::mqttPublish( "dbms/$opt_instance/database/$db/dbsize", $set, { maxCount => $opt_limit-$count });
				Mods::Metrology::prometheusPublish( "instance/$opt_instance/database/$db", $set, { prefix => 'metrology_dbms_dbsize_' });
				@resultSet = ();
			}
		}
	}
	Mods::Toops::msgOut( "$count published message(s)" );
}

# -------------------------------------------------------------------------------------------------
# publish all tables rows count for the specified database
#  this is an error if no database has been specified on the command-line
#  if we have asked for a service, we may have several databases
sub doTablesCount {
	my $count = 0;
	if( !scalar @databases ){
		Mods::Toops::msgErr( "no database specified, unable to count rows in tables.." );
	} else {
		foreach my $db ( @databases ){
			Mods::Toops::msgOut( "publishing tables rows count on '$hostConfig->{name}\\$opt_instance\\$db'..." );
			last if $count >= $opt_limit && $opt_limit >= 0;
			my $tables = Mods::Toops::ttpFilter( `dbms.pl list -instance $opt_instance -database $db -listtables` );
			foreach my $tab ( @{$tables} ){
				last if $count >= $opt_limit && $opt_limit >= 0;
				my $sql = "use $db; select count(*) as rows_count from $tab";
				my $out = Mods::Toops::ttpFilter( `dbms.pl sql -instance $opt_instance -command \"$sql\"` );
				my @resultSet = ();
				foreach my $line ( @{$out} ){
					next if $line =~ /Changed database context/;
					next if $line =~ /rows affected/;
					push( @resultSet, $line );
				}
				my $set = Mods::Metrology::interpretResultSet( @resultSet );
				$count += Mods::Metrology::mqttPublish( "dbms/$opt_instance/database/$db/table/$tab", $set );
				Mods::Metrology::prometheusPublish( "instance/$opt_instance/database/$db/table/$tab", $set, { prefix => 'metrology_dbms_' });
			}
		}
	}
	Mods::Toops::msgOut( "$count published message(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"service=s"			=> \$opt_service,
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"dbsize!"			=> \$opt_dbsize,
	"tabcount!"			=> \$opt_tabcount,
	"limit=i"			=> \$opt_limit )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found service='$opt_service'" );
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found dbsize='".( $opt_dbsize ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found tabcount='".( $opt_tabcount ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found limit='$opt_limit'" );

# depending of the measurement option, may have a service or an instance plus maybe a database
# must have -service or -instance + -database
if( $opt_service ){
	if( $opt_instance || $opt_database ){
		Mods::Toops::msgErr( "'--service' option is exclusive of '--instance' and '--database' options" );
	} elsif( !exists( $hostConfig->{Services}{$opt_service} )){
		Mods::Toops::msgErr( "service='$opt_service' not defined in host configuration" );
	} else {
		$opt_instance = $hostConfig->{Services}{$opt_service}{instance} if exists $hostConfig->{Services}{$opt_service}{instance};
		Mods::Toops::msgVerbose( "setting instance='$opt_instance'" );
		@databases = @{$hostConfig->{Services}{$opt_service}{databases}} if exists $hostConfig->{Services}{$opt_service}{databases};
		Mods::Toops::msgVerbose( "setting databases='".join( ', ', @databases )."'" );
	}
} else {
	push( @databases, $opt_database ) if $opt_database;
}

$opt_instance = $defaults->{instance} if !$opt_instance;
my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

# if a database has been specified, check that it exists
if( scalar @databases ){
	foreach my $db ( @databases ){
		my $exists = Mods::Dbms::checkDatabaseExists( $opt_instance, $db );
		if( !$exists ){
			Mods::Toops::msgErr( "database '$db' doesn't exist" );
		}
	}
}

# if no option is given, have a warning message
if( !$opt_dbsize && !$opt_tabcount ){
	Mods::Toops::msgWarn( "no measure has been requested, exiting gracefully" );

} elsif( !Mods::Toops::errs()){
	doDbSize() if $opt_dbsize;
	doTablesCount() if $opt_tabcount;
}

Mods::Toops::ttpExit();