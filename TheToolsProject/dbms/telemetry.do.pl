# @(#) get and publish some databases telemetry data
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        service name [${service}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]dbsize            get databases size for the specified instance [${dbsize}]
# @(-) --[no]tabcount          get tables rows count for the specified database [${tabcount}]
# @(-) --limit=<limit>         limit the MQTT published messages [${limit}]
# @(-) --[no]mqtt              publish the metrics to the messaging MQTT-based system [${mqtt}]
# @(-) --[no]http              publish the metrics to the PushGateway HTTP-based system [${http}]
# @(-) --[no]text              publish the metrics to the TextFile Collector system [${text}]
#
# @(@) When limiting the published messages, be conscious that the '--dbsize' option provides 6 messages per database.
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

use TTP::DBMS;
use TTP::Service;
use TTP::Telemetry;

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	instance => 'MSSQLSERVER',
	database => '',
	dbsize => 'no',
	tabcount => 'no',
	limit => -1,
	mqtt => 1,
	http => 1,
	text => 1
};

my $opt_service = $defaults->{service};
my $opt_instance = '';
my $opt_instance_set = false;
my $opt_database = $defaults->{database};
my $opt_dbsize = false;
my $opt_tabcout = false;
my $opt_limit = $defaults->{limit};
my $opt_mqtt = false;
my $opt_http = false;
my $opt_text = false;

# may be overriden by the service if specified
my $jsonable = $ttp->node();
my $dbms = undef;

# list of databases to be checked
my $databases = [];

# note that the sp_spaceused stored procedure returns:
# - TWO resuts sets
# - and that units are in the data: we move them to the column names
# below a sample of the got result from "dbms.pl sql -tabular -multiple" command
=pod
+---------------+---------------+-------------------+
| database_size | database_name | unallocated space |
+---------------+---------------+-------------------+
| 54.75 MB      | Dom1          | 9.91 MB           |
+---------------+---------------+-------------------+
+--------+----------+------------+----------+
| unused | reserved | index_size | data     |
+--------+----------+------------+----------+
| 752 KB | 42464 KB | 2216 KB    | 39496 KB |
+--------+----------+------------+----------+
=cut

# -------------------------------------------------------------------------------------------------
# get the two result sets from sp_spaceused stored procedure
# returns a ready-to-be-published consolidated result set
sub _interpretDbResultSet {
	my ( $sets ) = @_;
	my $result = {};
	foreach my $set ( @{$sets} ){
		my $row = @{$set}[0];
		foreach my $key ( keys %{$row} ){
			# only publish numeric datas
			next if $key eq "database_name";
			# moving the unit to the column name
			my $data = $row->{$key};
			$key =~ s/\s/_/g;
			my @words = split( /\s+/, $data );
			$result->{$key.'_'.$words[1]} = $words[0];
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# publish all databases sizes for the specified instance
# if a service has been specified, only consider the databases of this service
# if only an instance has been specified, then search for all databases of this instance
# at the moment, a service is stucked to a single instance
sub doDbSize {
	msgOut( "publishing databases size on '$hostConfig->{name}\\$opt_instance'..." );
	my $mqttCount = 0;
	my $httpCount = 0;
	my $list = [];
	my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
	my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
	if( $opt_service ){
		$list = \@databases;
	} elsif( !$opt_database ){
		$list = ttpFilter( `dbms.pl list -instance $opt_instance -listdb -nocolored $dummy $verbose` );
	} else {
		push( @{$list}, $opt_database );
	}
	foreach my $db ( @{$list} ){
		last if $mqttCount >= $opt_limit && $opt_limit >= 0;
		msgOut( "  database '$db'" );
		# sp_spaceused provides two results sets, where each one only contains one data row
		my $resultSets = TTP::DBMS::hashFromTabular( ttpFilter( `dbms.pl sql -instance $opt_instance -command \"use $db; exec sp_spaceused;\" -tabular -multiple -nocolored $dummy $verbose` ));
		my $set = _interpretDbResultSet( $resultSets );
		foreach my $key ( keys %{$set} ){
			`telemetry.pl publish -metric $key -value $set->{$key} -label instance=$opt_instance -label database=$db -httpPrefix ttp_dbms_database_size_ -mqttPrefix dbsize/ -nocolored $dummy $verbose`;
			my $rc = $?;
			msgVerbose( "doDbSize() got rc=$rc" );
			$mqttCount += 1 if !$rc;
			$httpCount += 1 if !$rc;
		}
	}
	msgOut( "$mqttCount message(s) published on MQTT bus, $httpCount metric(s) published to HTTP gateway" );
}

# -------------------------------------------------------------------------------------------------
# publish all tables rows count for the specified database
#  this is an error if no database has been specified on the command-line
#  if we have asked for a service, we may have several databases
sub doTablesCount {
	my $mqttCount = 0;
	my $httpCount = 0;
	if( !scalar @databases ){
		msgErr( "no database specified, unable to count rows in tables.." );
	} else {
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		foreach my $db ( @databases ){
			msgOut( "publishing tables rows count on '$hostConfig->{name}\\$opt_instance\\$db'..." );
			last if $mqttCount >= $opt_limit && $opt_limit >= 0;
			my $tables = ttpFilter( `dbms.pl list -instance $opt_instance -database $db -listtables -nocolored $dummy $verbose` );
			foreach my $tab ( @{$tables} ){
				last if $mqttCount >= $opt_limit && $opt_limit >= 0;
				msgOut( "  table '$tab'" );
				my $resultSet = TTP::DBMS::hashFromTabular( ttpFilter( `dbms.pl sql -instance $opt_instance -command \"use $db; select count(*) as rows_count from $tab;\" -tabular -nocolored $dummy $verbose` ));
				my $set = $resultSet->[0];
				$set->{rows_count} = 0 if !defined $set->{rows_count};
				foreach my $key ( keys %{$set} ){
					`telemetry.pl publish -metric $key -value $set->{$key} -label instance=$opt_instance -label database=$db -label table=$tab -httpPrefix ttp_dbms_database_table_ -nocolored $dummy $verbose`;
					my $rc = $?;
					msgVerbose( "doTablesCount() got rc=$rc" );
					$mqttCount += 1 if !$rc;
					$httpCount += 1 if !$rc;
				}
			}
		}
	}
	msgOut( "$mqttCount message(s) published on MQTT bus, $httpCount metric(s) published to HTTP gateway" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"service=s"			=> \$opt_service,
	"instance=s"		=> sub {
		my( $opt_name, $opt_value ) = @_;
		$opt_instance = $opt_value;
		$opt_instance_set = true;
	},
	"database=s"		=> \$opt_database,
	"dbsize!"			=> \$opt_dbsize,
	"tabcount!"			=> \$opt_tabcount,
	"limit=i"			=> \$opt_limit,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http,
	"text!"				=> \$opt_text )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $running->colored() ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $running->dummy() ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $running->verbose() ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found instance='$opt_instance'" );
msgVerbose( "found database='$opt_database'" );
msgVerbose( "found dbsize='".( $opt_dbsize ? 'true':'false' )."'" );
msgVerbose( "found tabcount='".( $opt_tabcount ? 'true':'false' )."'" );
msgVerbose( "found limit='$opt_limit'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );
msgVerbose( "found text='".( $opt_text ? 'true':'false' )."'" );

# must have either -service or -instance options
# compute instance from service
my $count = 0;
$count += 1 if $opt_service;
$count += 1 if $opt_instance_set;
if( $count == 0 ){
	msgErr( "must have one of '--service' or '--instance' option, none found" );
} elsif( $count > 1 ){
	msgErr( "must have one of '--service' or '--instance' option, both found" );
} elsif( $opt_service ){
	if( $jsonable->hasService( $opt_service )){
		$jsonable = TTP::Service->new( $ttp, { service => $opt_service });
		$opt_instance = $jsonable->var([ 'DBMS', 'instance' ]);
	} else {
		msgErr( "service '$opt_service' if not defined on current execution node" ) ;
	}
}

# instanciates the DBMS class
$dbms = TTP::DBMS->new( $ttp, { instance => $opt_instance }) if !TTP::errs();

# database(s) can be specified in the command-line, or can come from the service
if( $opt_database ){
	push( @{$databases}, $opt_database );
} elsif( $opt_service ){
	$databases = $jsonable->var([ 'DBMS', 'databases' ]);
	msgVerbose( "setting databases='".join( ', ', @{$databases} )."'" );
}

# all databases must exist in the instance
if( scalar @{$databases} ){
	foreach my $db ( @{$databases} ){
		my $exists = $dbms->databaseExists( $db );
		if( !$exists ){
			msgErr( "database '$db' doesn't exist in the '$opt_instance' instance" );
		}
	}
} else {
	msgErr( "'--database' option is required (or '--service'), but none is specified" );
}

# if no option is given, have a warning message
if( !$opt_dbsize && !$opt_tabcount ){
	msgWarn( "no measure has been requested, exiting" );

} elsif( !TTP::errs()){
	doDbSize() if $opt_dbsize;
	doTablesCount() if $opt_tabcount;
}

TTP::exit();
