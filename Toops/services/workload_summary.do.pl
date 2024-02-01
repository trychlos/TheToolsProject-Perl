# @(#) Print a workload summary in order to get ride of CMD.EXE special chatracters interpretation
#
# @(#) This verb display a summary of the executed commands found in 'command' environment variable,
# @(#) along with their exit code in 'rc' environment variable.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --me=<name>             the environment variable name which holds the workload name [${me}]
# @(-) --commands=<name>       the environment variable name which holds the commands [${commands}]
# @(-) --start=<name>          the environment variable name which holds the starting timestamp [${start}]
# @(-) --end=<name>            the environment variable name which holds the ending timestamp [${end}]
# @(-) --rc=<name>             the environment variable name which holds the return codes [${rc}]
# @(-) --count=<count>         the count of commands to deal with [${count}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	me => 'ME',
	commands => 'command',
	start => 'start',
	end => 'end',
	rc => 'rc',
	count => 0
};

my $opt_me = $defaults->{me};
my $opt_commands = $defaults->{commands};
my $opt_start = $defaults->{start};
my $opt_end = $defaults->{end};
my $opt_rc = $defaults->{rc};
my $opt_count = $defaults->{count};

# -------------------------------------------------------------------------------------------------
# pad the provided string until the specified length
sub pad {
	my( $str, $length, $pad ) = @_;
	while( length( $str ) < $length ){
		$str .= $pad;
	}
	return $str;
}

# -------------------------------------------------------------------------------------------------
# print a funny workload summary
sub printSummary {
	# get the CMD.EXE results from the environment
	my @results = ();
	my $maxLength = 0;
	for( my $i=1 ; $i<=$opt_count ; ++$i ){
		my $command = $ENV{$opt_commands.'['.$i.']'};
		push( @results, {
			command => $command,
			start => $ENV{$opt_start.'['.$i.']'},
			end => $ENV{$opt_end.'['.$i.']'},
			rc => $ENV{$opt_rc.'['.$i.']'}
		});
		if( length $command > $maxLength ){
			$maxLength = length $command;
		}
	}
	# display the summary
	my $totLength = $maxLength + 63;
	print pad( "+", $totLength-1, '=' )."+".EOL;
	print pad( "| $ENV{$opt_me} WORKLOAD SUMMARY", $totLength-1, ' ' )."|".EOL;
	print pad( "|", $maxLength+8, ' ' ).pad( "started at", 25, ' ' ).pad( "ended at", 25, ' ' )." RC |".EOL;
	print pad( "+", $maxLength+6, '-' ).pad( "+", 25, '-' ).pad( "+", 25, '-' )."+-----+".EOL;
	foreach my $it ( @results ){
		print pad( "| $it->{command}", $maxLength+6, ' ' ).pad( "| $it->{start}", 25, ' ' ).pad( "| $it->{end}", 25, ' ' ).sprintf( "| %3d |", $it->{rc} ).EOL;
	}
	print "+".pad( "", $totLength-2, '=' )."+".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"me=s"				=> \$opt_me,
	"commands=s"		=> \$opt_commands,
	"start=s"			=> \$opt_start,
	"end=s"				=> \$opt_end,
	"rc=s"				=> \$opt_rc,
	"count=i"			=> \$opt_count	)){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::doHelpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found me='$opt_me'" );
Mods::Toops::msgVerbose( "found commands='$opt_commands'" );
Mods::Toops::msgVerbose( "found start='$opt_start'" );
Mods::Toops::msgVerbose( "found end='$opt_end'" );
Mods::Toops::msgVerbose( "found rc='$opt_rc'" );
Mods::Toops::msgVerbose( "found count='$opt_count'" );

if( !Mods::Toops::errs()){
	printSummary();
}

Mods::Toops::ttpExit();
