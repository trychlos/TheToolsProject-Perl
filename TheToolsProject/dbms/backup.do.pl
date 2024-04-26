# @(#) run a database backup
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --service=<name>        service name [${service}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]full              operate a full backup [${full}]
# @(-) --[no]diff              operate a differential backup [${diff}]
# @(-) --[no]compress          compress the outputed backup [${compress}]
# @(-) --output=<filename>     target filename [${output}]
#
# @(@) Note 1: remind that differential backup is the difference of the current state and the last full backup.
# @(@) Note 2: the default output filename is computed as:
# @(@)         <instance_backup_path>\<yymmdd>\<host>-<instance>-<database>-<yymmdd>-<hhmiss>-<mode>.backup
# @(@) Note 3: "dbms.pl backup" provides an execution report according to the configured options.
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

use File::Spec;
use Time::Piece;

use TTP::Dbms;
use TTP::Service;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	service => '',
	instance => 'MSSQLSERVER',
	database => '',
	full => 'no',
	diff => 'no',
	compress => 'no',
	output => 'DEFAUT'
};

my $opt_service = $defaults->{service};
my $opt_instance = '';
my $opt_database = $defaults->{database};
my $opt_full = false;
my $opt_diff = false;
my $opt_compress = false;
my $opt_output = '';

# this host configuration
my $hostConfig = TTP::getHostConfig();

# list of databases to be backuped
my $databases = [];

# -------------------------------------------------------------------------------------------------
# backup the source database to the target backup file
sub doBackup {
	my $mode = $opt_full ? 'full' : 'diff';
	my $count = 0;
	my $asked = 0;
	foreach my $db ( @{$databases} ){
		msgOut( "backuping database '$hostConfig->{name}\\$opt_instance\\$db'" );
		my $res = TTP::Dbms::backupDatabase({
			instance => $opt_instance,
			database => $db,
			output => $opt_output,
			mode => $mode,
			compress => $opt_compress
		});
		# retain last full and last diff
		my $data = {
			instance => $opt_instance,
			database => $db,
			mode => $mode,
			output => ( $res->{status} ? $res->{output} : "" ),
			compress => $opt_compress
		};
		TTP::executionReport({
			file => {
				data => $data
			},
			mqtt => {
				topic => "$TTPVars->{config}{host}{name}/executionReport/$ttp->{run}{command}{basename}/$ttp->{run}{verb}{name}/$opt_instance/$db",
				data => $data,
				options => "-retain",
				excludes => [
					'instance',
					'database',
					'cmdline',
					'command',
					'verb',
					'host'
				]
			}
		});
		$asked += 1;
		$count += 1 if $res->{status};
	}
	my $str = "$count/$asked backuped database(s)";
	if( $count == $asked ){
		msgOut( "success: $str" );
	} else {
		msgErr( "NOT OK: $str" );
	}
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
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full!"				=> \$opt_full,
	"diff!"				=> \$opt_diff,
	"compress!"			=> \$opt_compress,
	"output=s"			=> \$opt_output )){

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
msgVerbose( "found full='".( $opt_full ? 'true':'false' )."'" );
msgVerbose( "found diff='".( $opt_diff ? 'true':'false' )."'" );
msgVerbose( "found compress='".( $opt_compress ? 'true':'false' )."'" );
msgVerbose( "found output='$opt_output'" );

# must have -service or -instance + -database
if( $opt_service ){
	my $serviceConfig = undef;
	if( $opt_instance ){
		msgErr( "'--service' option is exclusive of '--instance' option" );
	} else {
		$serviceConfig = TTP::Service::serviceConfig( $hostConfig, $opt_service );
		if( $serviceConfig ){
			$opt_instance = TTP::Dbms::checkInstanceName( undef, { serviceConfig => $serviceConfig });
			if( $opt_instance ){
				msgVerbose( "setting instance='$opt_instance'" );
				if( $opt_database ){
					push( @{$databases}, $opt_database );
				} else {
					$databases = $serviceConfig->{DBMS}{databases} if exists  $serviceConfig->{DBMS}{databases};
					msgVerbose( "setting databases='".join( ', ', @{$databases} )."'" );
				}
			}
		} else {
			msgErr( "service='$opt_service' not defined in host configuration" );
		}
	}
} else {
	push( @{$databases}, $opt_database ) if $opt_database;
}

$opt_instance = $defaults->{instance} if !$opt_instance;
my $instance = TTP::Dbms::checkInstanceName( $opt_instance );

if( scalar @{$databases} ){
	foreach my $db ( @{$databases} ){
		my $exists = TTP::Dbms::checkDatabaseExists( $opt_instance, $db );
		if( !$exists ){
			msgErr( "database '$db' doesn't exist" );
		}
	}
} else {
	msgErr( "'--database' option is required (or '--service'), but is not specified" ) if !$opt_service;
}

my $count = 0;
$count += 1 if $opt_full;
$count += 1 if $opt_diff;
if( $count != 1 ){
	msgErr( "one of '--full' or '--diff' options must be specified" );
}

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
} elsif( scalar @{$databases} > 1 ){
	msgErr( "cowardly refuse to backup several databases in a single output file" );
}

if( !TTP::errs()){
	doBackup();
}

TTP::exit();
