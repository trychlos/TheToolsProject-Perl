# @(#) execute a SQL command or script on a DBMS instance
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]stdin             whether the sql command has to be read from stdin [${stdin}]
# @(-) --script=<filename>     the sql script filename [${script}]
# @(-) --[no]tabular           format the output as tabular data [${tabular}]
#
# @(@) The provided SQL script may or may not have a displayable result. Nonetheless, this verb will always display all the script output.
# @(@) In a Windows command prompt, use Ctrl+Z to terminate the stdin stream (or use a HERE document).
# @(@) Use Ctrl+D in a Unix terminal.
# @(@) '--dummy' option is ignored when SQL command is a SELECT sentence.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Path::Tiny;

use Mods::Dbms;
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	instance => 'MSSQLSERVER',
	stdin => 'no',
	script => '',
	tabular => 'yes'
};

my $opt_instance = $defaults->{instance};
my $opt_stdin = false;
my $opt_script = $defaults->{script};
my $opt_tabular = true;

# -------------------------------------------------------------------------------------------------
# execute the sql command to be read from stdin
sub execSqlCommand {
	my $command = '';
	while( <> ){
		$command .= $_;
	}
	Mods::Toops::msgVerbose( "got command='$command'" );
	Mods::Dbms::execSqlCommand( $command, { tabular => $opt_tabular });
}

# -------------------------------------------------------------------------------------------------
# execute the sql script
sub execSqlScript {
	my $sql = path( $opt_script )->slurp_utf8;
	Mods::Dbms::execSqlCommand( $sql, { tabular => $opt_tabular });
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
	"stdin!"			=> \$opt_stdin,
	"script=s"			=> \$opt_script,
	"tabular!"			=> \$opt_tabular )){

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
Mods::Toops::msgVerbose( "found instance='$opt_instance'" );
Mods::Toops::msgVerbose( "found stdin='".( $opt_stdin ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found script='$opt_script'" );
Mods::Toops::msgVerbose( "found tabular='".( $opt_tabular ? 'true':'false' )."'" );

# instance is mandatory
Mods::Dbms::checkInstanceOpt( $opt_instance );
# either -stdin or -script options must be specified and only one
my $count = 0;
$count += 1 if $opt_stdin;
$count += 1 if $opt_script;
if( $count != 1 ){
	Mods::Toops::msgErr( "either '--stdint' or '--script' option must be specified" );
} elsif( $opt_script ){
	if( ! -f $opt_script ){
		Mods::Toops::msgErr( "$opt_script: file is not found or not readable" );
	}
}

if( !Mods::Toops::errs()){
	execSqlCommand() if $opt_stdin;
	execSqlScript() if $opt_script;
}

Mods::Toops::ttpExit();
