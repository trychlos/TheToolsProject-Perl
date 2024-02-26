# @(#) execute a SQL command or script on a DBMS instance
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --instance=<name>       acts on the named instance [${instance}]
# @(-) --[no]stdin             whether the sql command has to be read from stdin [${stdin}]
# @(-) --script=<filename>     the sql script filename [${script}]
# @(-) --command=<command>     the sql command as a string [${command}]
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
	command => '',
	tabular => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_stdin = false;
my $opt_script = $defaults->{script};
my $opt_command = $defaults->{command};
my $opt_tabular = false;

# -------------------------------------------------------------------------------------------------
# Dbms::execSqlCommand returns a hash with:
# -result: true|false
# - output: an array of output
sub _result {
	my ( $res ) = @_;
	if( $res->{output} && scalar @{$res->{output}} && !$opt_tabular ){
		my $isHash = false;
		foreach my $it ( @{$res->{output}} ){
			$isHash = true if ref( $it ) eq 'HASH';
			print $it;
		}
		if( $isHash ){
			Mods::Toops::msgWarn( "result contains data, should have been displayed with '--tabular' option" );
		}
	}
	if( $res->{ok} ){
		Mods::Toops::msgOut( "success" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# execute the sql command to be read from stdin
sub execSqlStdin {
	my $command = '';
	while( <> ){
		$command .= $_;
	}
	chomp $command;
	Mods::Toops::msgVerbose( "executing '$command' from stdin" );
	my $res = Mods::Dbms::execSqlCommand( $command, { tabular => $opt_tabular });
	_result( $res );
}

# -------------------------------------------------------------------------------------------------
# execute the sql script
sub execSqlScript {
	Mods::Toops::msgVerbose( "executing from '$opt_script'" );
	my $sql = path( $opt_script )->slurp_utf8;
	Mods::Toops::msgVerbose( "sql='$sql'" );
	my $res = Mods::Dbms::execSqlCommand( $sql, { tabular => $opt_tabular });
	_result( $res );
}

# -------------------------------------------------------------------------------------------------
# execute the sql command to be read from stdin
sub execSqlCommand {
	Mods::Toops::msgVerbose( "executing command='$opt_command'" );
	my $res = Mods::Dbms::execSqlCommand( $opt_command, { tabular => $opt_tabular });
	_result( $res );
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
	"command=s"			=> \$opt_command,
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
Mods::Toops::msgVerbose( "found command='$opt_command'" );
Mods::Toops::msgVerbose( "found tabular='".( $opt_tabular ? 'true':'false' )."'" );

# instance is mandatory
Mods::Dbms::checkInstanceOpt( $opt_instance );
# either -stdin or -script or -command options must be specified and only one
my $count = 0;
$count += 1 if $opt_stdin;
$count += 1 if $opt_script;
$count += 1 if $opt_command;
if( $count != 1 ){
	Mods::Toops::msgErr( "either '--stdint' or '--script' or '--command' option must be specified" );
} elsif( $opt_script ){
	if( ! -f $opt_script ){
		Mods::Toops::msgErr( "$opt_script: file is not found or not readable" );
	}
}

if( !Mods::Toops::errs()){
	execSqlStdin() if $opt_stdin;
	execSqlScript() if $opt_script;
	execSqlCommand() if $opt_command;
}

Mods::Toops::ttpExit();
