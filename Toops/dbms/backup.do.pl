# @(#) run a database backup
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       database name [${database}]
# @(-) --[no]full              operate a full backup [${full}]
# @(-) --[no]diff              operate a differential backup [${diff}]
# @(-) --output=<filename>     target filename [${output}]
#
# @(@) Note: remind that differential backup is the difference of the current state and the last full backup.
# @(@) Note: the default output filename is computed as:
# @(@)       <instance_backup_path>\<yymmdd>\<host>-<instance>-<database>-<yymmdd>-<hhmiss>-<mode>.backup
#
# Copyright (@) 2023-2024 PWI Consulting

use Mods::Dbms;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	dummy => 'no',
	instance => 'MSSQLSERVER',
	database => '',
	full => 'no',
	diff => 'no',
	output => 'DEFAUT'
};

my $opt_dummy = false;
my $opt_instance = $defaults->{instance};
my $opt_database = $defaults->{database};
my $opt_full = false;
my $opt_diff = false;
my $opt_output = '';

# -------------------------------------------------------------------------------------------------
# backup the source database to the target backup file
sub doBackup {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "backuping database '$hostConfig->{name}\\$opt_instance\\$opt_database'" );
	my $res = Mods::Dbms::backupDatabase({
		instance => $opt_instance,
		database => $opt_database,
		output => $opt_output,
		mode => $opt_diff ? 'diff' : 'full',
		dummy => $opt_dummy
	});
	if( $res ){
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

=pod
Mods::Toops::getOptions([
	{
		key	 => 'instance',
		help => "address named instance",
		opt	 => '=s',
		var	 => \$opt_instance,
		def	 => $opt_instance_def
	},
	{
		key	 => 'database',
		help => "backup named database",
		opt	 => '=s',
		var	 => \$opt_database,
		def	 => $opt_database_def
	},
	{
		key	 => 'full',
		help => "whether to do a full backup",
		opt	 => '!',
		var	 => \$opt_full,
		def	 => $opt_full_def
	},
	{
		key	 => 'diff',
		help => "whether to do a differential backup",
		opt	 => '!',
		var	 => \$opt_diff,
		def	 => $opt_diff_def
	},
	{
		key	 => 'output',
		help => "output filename",
		opt	 => '=s',
		var	 => \$opt_output,
		def	 => $opt_output_def
	}
]);
=cut

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"dummy!"			=> \$opt_dummy,
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full!"				=> \$opt_full,
	"diff!"				=> \$opt_diff,
	"output=s"			=> \$opt_output )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found database='$opt_database'" );
Mods::Toops::msgVerbose( "found full='".( $opt_full ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found diff='".( $opt_diff ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found output='$opt_output'" );

my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

if( $opt_database ){
	my $exists = Mods::Dbms::checkDatabaseExists( $opt_instance, $opt_database );
	if( !$exists ){
		Mods::Toops::msgErr( "database '$opt_database' doesn't exist" );
	}
} else {
	Mods::Toops::msgErr( "'--database' option is required, but is not specified" );
}

my $count = 0;
$count += 1 if $opt_full;
$count += 1 if $opt_diff;
if( $count != 1 ){
	Mods::Toops::msgErr( "one of '--full' or '--diff' options must be specified" );
}

if( !$opt_output ){
	msgVerbose( "'--output' option not specified, will use the computed default" );
}

if( !Mods::Toops::errs()){
	doBackup();
}

Mods::Toops::ttpExit();
