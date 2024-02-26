# @(#) Print a workload summary in order to get ride of CMD.EXE special chatracters interpretation
#
# @(#) This verb display a summary of the executed commands found in 'command' environment variable,
# @(#) along with their exit code in 'rc' environment variable.
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --workload=<name>       the workload name [${workload}]
# @(-) --commands=<name>       the name of the environment variable which holds the commands [${commands}]
# @(-) --start=<name>          the name of the environment variable which holds the starting timestamp [${start}]
# @(-) --end=<name>            the name of the environment variable which holds the ending timestamp [${end}]
# @(-) --rc=<name>             the name of the environment variable which holds the return codes [${rc}]
# @(-) --count=<count>         the count of commands to deal with [${count}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	workload => '',
	commands => 'command',
	start => 'start',
	end => 'end',
	rc => 'rc',
	count => 0
};

my $opt_workload = $defaults->{workload};
my $opt_commands = $defaults->{commands};
my $opt_start = $defaults->{start};
my $opt_end = $defaults->{end};
my $opt_rc = $defaults->{rc};
my $opt_count = $defaults->{count};

# -------------------------------------------------------------------------------------------------
# pad the provided string until the specified length
sub _pad {
	return Mods::Toops::pad( @_ );
}

=pod
+=============================================================================================================================+
|  WORKLOAD SUMMARY                                                                                                           |
|                                                                       started at               ended at                  RC |
+---------------------------------------------------------------------+------------------------+------------------------+-----+
| dbms.pl backup -instance MSSQLSERVER -database inlingua17a -diff    | 2024-02-07 22:00:02,26 | 2024-02-07 22:00:02,98 |   0 |
| dbms.pl backup -instance MSSQLSERVER -database inlingua21 -diff     | 2024-02-07 22:00:02,98 | 2024-02-07 22:00:03,58 |   0 |
| dbms.pl backup -instance MSSQLSERVER -database TOM59331 -diff       | 2024-02-07 22:00:03,58 | 2024-02-07 22:00:04,59 |   0 |
+=============================================================================================================================+
|                                                                                                                             |
|                                                        EMPTY OUTPUT                                                         |
|                                                                                                                             |
+=============================================================================================================================+
=cut

# -------------------------------------------------------------------------------------------------
# print a funny workload summary
sub printSummary {
	# get the CMD.EXE results from the environment
	my @results = ();
	my $maxLength = 0;
	for( my $i=1 ; $i<=$opt_count ; ++$i ){
		my $command = $ENV{$opt_commands.'['.$i.']'};
		Mods::Toops::msgVerbose( "pushing i=$i command='$command'" );
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
	if( $opt_count == 0 ){
		$maxLength = 65; # arbitrary value long enough to get a pretty display (and the totLength be even)
	}
	# display the summary
	my $totLength = $maxLength + 63;
	print _pad( "+", $totLength-1, '=' )."+".EOL;
	print _pad( "| WORKLOAD SUMMARY for <$opt_workload>", $totLength-1, ' ' )."|".EOL;
	print _pad( "|", $maxLength+8, ' ' )._pad( "started at", 25, ' ' )._pad( "ended at", 25, ' ' )." RC |".EOL;
	print _pad( "+", $maxLength+6, '-' )._pad( "+", 25, '-' )._pad( "+", 25, '-' )."+-----+".EOL;
	# display the result or an empty output
	if( $opt_count > 0 ){
		my $i = 0;
		foreach my $it ( @results ){
			$i += 1;
			Mods::Toops::msgVerbose( "printing i=$i execution report" );
			print _pad( "| $it->{command}", $maxLength+6, ' ' )._pad( "| $it->{start}", 25, ' ' )._pad( "| $it->{end}", 25, ' ' ).sprintf( "| %3d |", $it->{rc} ).EOL;
		}
	} else {
		#print _pad( "|", $totLength-1, ' ' )."|".EOL;
		print _pad( "|", $totLength/2 - 6, ' ' )._pad( "EMPTY OUTPUT", $totLength/2 + 5, ' ' )."|".EOL;
		#print _pad( "|", $totLength-1, ' ' )."|".EOL;
	}
	print "+"._pad( "", $totLength-2, '=' )."+".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"workload=s"		=> \$opt_workload,
	"commands=s"		=> \$opt_commands,
	"start=s"			=> \$opt_start,
	"end=s"				=> \$opt_end,
	"rc=s"				=> \$opt_rc,
	"count=i"			=> \$opt_count	)){

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
Mods::Toops::msgVerbose( "found workload='$opt_workload'" );
Mods::Toops::msgVerbose( "found commands='$opt_commands'" );
Mods::Toops::msgVerbose( "found start='$opt_start'" );
Mods::Toops::msgVerbose( "found end='$opt_end'" );
Mods::Toops::msgVerbose( "found rc='$opt_rc'" );
Mods::Toops::msgVerbose( "found count='$opt_count'" );

if( !Mods::Toops::errs()){
	printSummary();
}

Mods::Toops::ttpExit();