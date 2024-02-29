# @(#) run a database backup
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --service=<name>        service name [${service}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]full              operate a full backup [${full}]
# @(-) --[no]diff              operate a differential backup [${diff}]
# @(-) --[no]compress          compress the outputed backup [${compress}]
# @(-) --output=<filename>     target filename [${output}]
#
# @(@) Note: remind that differential backup is the difference of the current state and the last full backup.
# @(@) Note: the default output filename is computed as:
# @(@)       <instance_backup_path>\<yymmdd>\<host>-<instance>-<database>-<yymmdd>-<hhmiss>-<mode>.backup
#
# Copyright (@) 2023-2024 PWI Consulting

use File::Spec;
use Time::Piece;

use Mods::Dbms;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
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
my $hostConfig = Mods::Toops::getHostConfig();

# list of databases to be backuped
my $databases = [];

# -------------------------------------------------------------------------------------------------
# backup the source database to the target backup file
sub doBackup {
	my $mode = $opt_full ? 'full' : 'diff';
	my $count = 0;
	my $asked = 0;
	foreach my $db ( @{$databases} ){
		Mods::Message::msgOut( "backuping database '$hostConfig->{name}\\$opt_instance\\$db'" );
		my $res = Mods::Dbms::backupDatabase({
			instance => $opt_instance,
			database => $db,
			output => $opt_output,
			mode => $mode,
			compress => $opt_compress
		});
		# retain last full and last diff
		Mods::Toops::execReportByCommand({
			instance => $opt_instance,
			database => $db,
			mode => $mode,
			output => $res->{output}
		}, {
			topic => [ 'instance', 'database', 'mode' ],
			retain => true
		});
		$asked += 1;
		$count += 1 if $res->{status};
	}
	my $str = "$count/$asked backuped database(s)";
	if( $count == $asked ){
		Mods::Message::msgOut( "success: $str" );
	} else {
		Mods::Message::msgErr( "NOT OK: $str" );
	}
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
	"full!"				=> \$opt_full,
	"diff!"				=> \$opt_diff,
	"compress!"			=> \$opt_compress,
	"output=s"			=> \$opt_output )){

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
Mods::Message::msgVerbose( "found service='$opt_service'" );
Mods::Message::msgVerbose( "found instance='$opt_instance'" );
Mods::Message::msgVerbose( "found database='$opt_database'" );
Mods::Message::msgVerbose( "found full='".( $opt_full ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found diff='".( $opt_diff ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found compress='".( $opt_compress ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found output='$opt_output'" );

# must have -service or -instance + -database
if( $opt_service ){
	if( $opt_instance || $opt_database ){
		Mods::Message::msgErr( "'--service' option is exclusive of '--instance' and '--database' options" );
	} elsif( !exists( $hostConfig->{Services}{$opt_service} )){
		Mods::Message::msgErr( "service='$opt_service' not defined in host configuration" );
	} else {
		$opt_instance = $hostConfig->{Services}{$opt_service}{instance} if exists $hostConfig->{Services}{$opt_service}{instance};
		Mods::Message::msgVerbose( "setting instance='$opt_instance'" );
		$databases = $hostConfig->{Services}{$opt_service}{databases} if exists $hostConfig->{Services}{$opt_service}{databases};
		Mods::Message::msgVerbose( "setting databases='".join( ', ', @{$databases} )."'" );
	}
} else {
	push( @{$databases}, $opt_database ) if $opt_database;
}

$opt_instance = $defaults->{instance} if !$opt_instance;
my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

if( scalar @{$databases} ){
	foreach my $db ( @{$databases} ){
		my $exists = Mods::Dbms::checkDatabaseExists( $opt_instance, $db );
		if( !$exists ){
			Mods::Message::msgErr( "database '$db' doesn't exist" );
		}
	}
} else {
	Mods::Message::msgErr( "'--database' option is required (or '--service'), but is not specified" );
}

my $count = 0;
$count += 1 if $opt_full;
$count += 1 if $opt_diff;
if( $count != 1 ){
	Mods::Message::msgErr( "one of '--full' or '--diff' options must be specified" );
}

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
} elsif( scalar @{$databases} > 1 ){
	Mods::Message::msgErr( "cowardly refuse to backup several databases in a single output file" );
}

if( !Mods::Toops::errs()){
	doBackup();
}

Mods::Toops::ttpExit();
