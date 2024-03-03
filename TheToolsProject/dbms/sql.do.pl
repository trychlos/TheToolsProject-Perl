# @(#) execute a SQL command or a script on a DBMS instance
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
# @(-) --[no]multiple          whether we expect several result sets [${multiple}]
#
# @(@) The provided SQL script may or may not have a displayable result. Nonetheless, this verb will always display all the script output.
# @(@) In a Windows command prompt, use Ctrl+Z to terminate the stdin stream (or use a HERE document).
# @(@) Use Ctrl+D in a Unix terminal.
# @(@) '--dummy' option is ignored when SQL command is a SELECT sentence.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use Path::Tiny;

use Mods::Constants qw( :all );
use Mods::Dbms;
use Mods::Message;
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
	tabular => 'no',
	multiple => 'no'
};

my $opt_instance = $defaults->{instance};
my $opt_stdin = false;
my $opt_script = $defaults->{script};
my $opt_command = $defaults->{command};
my $opt_tabular = false;
my $opt_multiple = false;

# -------------------------------------------------------------------------------------------------
# Dbms::execSqlCommand returns a hash with:
# - ok: true|false
# - result: the result set as an array ref
#   an array of hashes for a single set, or an array of arrays of hashes in case of a multiple result sets
# - stdout: an array of what has been printed (which are often error messages)
sub _result {
	my ( $res ) = @_;
	if( $res->{ok} && scalar @{$res->{result}} && !$opt_tabular ){
		my $isHash = false;
		foreach my $it ( @{$res->{result}} ){
			$isHash = true if ref( $it ) eq 'HASH';
			print $it if !ref( $it );
		}
		if( $isHash ){
			Mods::Message::msgWarn( "result contains data, should have been displayed with '--tabular' option" );
		}
	}
	if( $res->{ok} ){
		Mods::Message::msgOut( "success" );
	} else {
		Mods::Message::msgErr( "NOT OK" );
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
	Mods::Message::msgVerbose( "executing '$command' from stdin" );
	_result( Mods::Dbms::execSqlCommand( $command, { tabular => $opt_tabular, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql script
sub execSqlScript {
	Mods::Message::msgVerbose( "executing from '$opt_script'" );
	my $sql = path( $opt_script )->slurp_utf8;
	Mods::Message::msgVerbose( "sql='$sql'" );
	_result( Mods::Dbms::execSqlCommand( $sql, { tabular => $opt_tabular, multiple => $opt_multiple }));
}

# -------------------------------------------------------------------------------------------------
# execute the sql command to be read from stdin
sub execSqlCommand {
	Mods::Message::msgVerbose( "executing command='$opt_command'" );
	_result( Mods::Dbms::execSqlCommand( $opt_command, { tabular => $opt_tabular, multiple => $opt_multiple }));
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
	"tabular!"			=> \$opt_tabular,
	"multiple!"			=> \$opt_multiple )){

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
Mods::Message::msgVerbose( "found stdin='".( $opt_stdin ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found script='$opt_script'" );
Mods::Message::msgVerbose( "found command='$opt_command'" );
Mods::Message::msgVerbose( "found tabular='".( $opt_tabular ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found multiple='".( $opt_multiple ? 'true':'false' )."'" );

# instance is mandatory
Mods::Dbms::checkInstanceOpt( $opt_instance );
# either -stdin or -script or -command options must be specified and only one
my $count = 0;
$count += 1 if $opt_stdin;
$count += 1 if $opt_script;
$count += 1 if $opt_command;
if( $count != 1 ){
	Mods::Message::msgErr( "either '--stdint' or '--script' or '--command' option must be specified" );
} elsif( $opt_script ){
	if( ! -f $opt_script ){
		Mods::Message::msgErr( "$opt_script: file is not found or not readable" );
	}
}

if( !Mods::Toops::errs()){
	execSqlStdin() if $opt_stdin;
	execSqlScript() if $opt_script;
	execSqlCommand() if $opt_command;
}

Mods::Toops::ttpExit();
