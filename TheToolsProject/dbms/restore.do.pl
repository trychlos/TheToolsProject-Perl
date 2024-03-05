# @(#) restore a database
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --instance=<name>       Sql Server instance name [${instance}]
# @(-) --database=<name>       target database name [${database}]
# @(-) --full=<filename>       restore from this full backup [${full}]
# @(-) --diff=<filename>       restore with this differential backup [${diff}]
# @(-) --[no]verifyonly        only check the backup restorability [${verifyonly}]
#
# @(@) Note 1: you must at least provide a full backup to restore, and may also provide an additional differential backup file.
# @(@) Note 2: target database is mandatory unless you only want a backup restorability check, in which case '--dummy' option is not honored.
# @(@) Note 3: "dbms.pl restore" provides an execution report according to the configured options.
#
# Copyright (@) 2023-2024 PWI Consulting

use Mods::Constants qw( :all );
use Mods::Dbms;
use Mods::Message;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	instance => 'MSSQLSERVER',
	database => '',
	full => '',
	diff => '',
	verifyonly => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_database = $defaults->{database};
my $opt_full = $defaults->{full};
my $opt_diff = $defaults->{diff};
my $opt_verifyonly = false;

my $fname = undef;

# -------------------------------------------------------------------------------------------------
# restore the provided backup file
sub doRestore {
	my $hostConfig = Mods::Toops::getHostConfig();
	if( $opt_verifyonly ){
		Mods::Message::msgOut( "verifying the restorability of '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	} else {
		Mods::Message::msgOut( "restoring database '$hostConfig->{name}\\$opt_instance\\$opt_database' from '$opt_full'".( $opt_diff ? ", with additional diff" : "" )."..." );
	}
	my $res = Mods::Dbms::restoreDatabase({
		instance => $opt_instance,
		database => $opt_database,
		full => $opt_full,
		diff => $opt_diff,
		verifyonly => $opt_verifyonly
	});
	if( !$opt_verifyonly ){
		# if we have restore something (not just verified the backup files), then we create an execution report
		#  with the same properties and options than dbms.pl backup
		my $mode = $opt_diff ? 'diff' : 'full';
		my $data = {
			instance => $opt_instance,
			database => $opt_database,
			full => $opt_full,
			diff => $opt_diff || '',
			mode => $mode
		};
		Mods::Toops::executionReport({
			file => {
				data => $data
			},
			mqtt => {
				data => $data,
				topic => "$TTPVars->{config}{host}{name}/executionReport/$TTPVars->{run}{command}{basename}/$TTPVars->{run}{verb}{name}/$opt_instance/$db/$mode",
				options => "-retain"
			}
		});
	}
	if( $res ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
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
	"instance=s"		=> \$opt_instance,
	"database=s"		=> \$opt_database,
	"full=s"			=> \$opt_full,
	"diff=s"			=> \$opt_diff,
	"verifyonly!"		=> \$opt_verifyonly )){

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
Mods::Message::msgVerbose( "found instance='$opt_instance'" );
Mods::Message::msgVerbose( "found database='$opt_database'" );
Mods::Message::msgVerbose( "found full='$opt_full'" );
Mods::Message::msgVerbose( "found diff='$opt_diff'" );
Mods::Message::msgVerbose( "found verifyonly='".( $opt_verifyonly ? 'true':'false' )."'" );

my $instance = Mods::Dbms::checkInstanceOpt( $opt_instance );

Mods::Message::msgErr( "'--database' option is mandatory, but is not specified" ) if !$opt_database && !$opt_verifyonly;
Mods::Message::msgErr( "'--full' option is mandatory, but is not specified" ) if !$opt_full;
Mods::Message::msgErr( "$opt_diff: file not found or not readable" ) if $opt_diff && ! -f $opt_diff;

if( !Mods::Toops::errs()){
	doRestore();
}

Mods::Toops::ttpExit();
