# @(#) manage scheduled tasks
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --task=<name>           apply to specified task(s) [${task}]
# @(-) --[no]list              list the scheduled tasks [${list}]
# @(-) --[no]status            display the status of the named task [${status}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	task => '',
	list => 'no',
	status => 'no'
};

my $opt_task = $defaults->{task};
my $opt_list = false;
my $opt_status = false;

# -------------------------------------------------------------------------------------------------
# list the scheduled tasks (once for each)
sub doListTasks {
	if( $opt_task ){
		msgOut( "listing tasks filtered on '$opt_task' name..." );
	} else {
		msgOut( "listing all tasks..." );
	}
	my $count = 0;
	my $stdout = `schtasks /Query /fo list`;
	my $res = $? == 0;
	my @lines = split( /[\r\n]/, $stdout );
	my @tasks = grep( /TaskName:/, @lines );
	if( $opt_task ){
		@tasks = grep( /$opt_task/i, @tasks );
	}
	my $uniqs = {};
	foreach my $it ( @tasks ){
		my @words = split( /\s+/, $it );
		if( !exists( $uniqs->{$words[1]} )){
			$count += 1;
			$uniqs->{$words[1]} = true;
			print "  $words[1]".EOL;
		}
	}
	if( $res ){
		msgOut( "found $count tasks" );
	} else {
		msgErr( "NOT OK" );
	}
}

# -------------------------------------------------------------------------------------------------
# display the status of a task
sub doTaskStatus {
	msgOut( "displaying the '$opt_task' task status..." );
	my $stdout = `schtasks /Query /fo table /TN $opt_task`;
	my $res = $? == 0;
	my @words = split( /\\/, $opt_task );
	my $name = $words[scalar( @words )-1];
	my @lines = split( /[\r\n]/, $stdout );
	my @props = grep( /$name/, @lines );
	@words = split( /\s+/, $props[0] );
	print "  $name: $words[2]".EOL;
	if( $res ){
		msgOut( "success" );
	} else {
		msgErr( "NOT OK" );
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
	"task=s"			=> \$opt_task,
	"list!"				=> \$opt_list,
	"status!"			=> \$opt_status	)){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found task='$opt_task'" );
msgVerbose( "found list='".( $opt_list ? 'true':'false' )."'" );
msgVerbose( "found status='".( $opt_status ? 'true':'false' )."'" );

# a task name is mandatory when asking for the status
msgErr( "a task name is mandatory when asking for a status" ) if $opt_status && !$opt_task;

if( !ttpErrs()){
	doListTasks() if $opt_list;
	doTaskStatus() if $opt_status && $opt_task;
}

ttpExit();
