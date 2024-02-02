# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]services          list defined services [${services}]
# @(-) --[no]workloads         list used workloads [${workloads}]
# @(-) --workload=<name>       display the detailed tasks for the named workload [${workload}]
# @(-) --[no]commands          display only the commands for the named workload [${commands}]
# @(-) --[no]hidden            also display hidden services [${hidden}]
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	services => 'no',
	workloads => 'no',
	workload => '',
	commands => 'no',
	hidden => 'no'
};

my $opt_services = false;
my $opt_workloads = false;
my $opt_workload = $defaults->{workload};
my $opt_commands = false;
my $opt_hidden = false;

# -------------------------------------------------------------------------------------------------
# list the defined DBMS instances (which may be not all the running instances)
sub listDbms {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying DBMS instances defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedDBMSInstances( $config );
	foreach my $it ( @list ){
		Mods::Toops::msgOut( PREFIX.$it );
	}
	Mods::Toops::msgOut( scalar @list." found defined DBMS instance(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all the defined services on this host
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying services defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedServices( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @list." found defined service(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all the workloads used on this host
sub listWorkloads {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workloads used on $hostConfig->{name}..." );
	my $list = Mods::Services::getUsedWorkloads( $hostConfig );
	my @names = keys %{$list};
	my @sorted = sort @names;
	foreach my $it ( @sorted ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @sorted." found used workload(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all (but only) the commands in this workload
sub listWorkloadCommands {
	#Mods::Services::listWorkloadTasksCommands( $opt_workload );
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workload commands defined in $hostConfig->{name}\\$opt_workload..." );
	my $list = Mods::Services::getUsedWorkloads( $hostConfig );
	my $count = 0;
	foreach my $it ( @{$list->{$opt_workload}} ){
		if( exists( $it->{commands} )){
			foreach my $command ( @{$it->{commands}} ){
				print " $command".EOL;
				$count += 1;
			}
		}
	}
	Mods::Toops::msgOut( "$count found defined command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the detailed tasks for the specified workload
sub listWorkloadDetails {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying detailed workload tasks defined in $hostConfig->{name}\\$opt_workload..." );
	my $list = Mods::Services::getUsedWorkloads( $hostConfig );
	foreach my $it ( @{$list->{$opt_workload}} ){
		printWorkloadTask( $it );
	}
	Mods::Toops::msgOut( scalar @{$list->{$opt_workload}}." found defined task(s)" );
}

# -------------------------------------------------------------------------------------------------
# print the detail of a task
sub printWorkloadTask {
	my ( $task ) = @_;
	# if we have a name, make it the first line
	if( exists( $task->{name} )){
		print "+ $task->{name}".EOL;
	} else {
		print "+ (unnamed)".EOL;
	}
	# print other keys
	# we manage one level array/hash to be able to display at least commands
	foreach my $key ( sort keys %{$task} ){
		if( $key ne 'name' ){
			listWorkloadTaskData( $task, $key, "  " );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# recursively print arrays/hashes
# item is a hash and we want print the value associated with the key in the item hash
sub listWorkloadTaskData {
	my ( $item, $key, $prefix ) = @_;
	my $type = ref( $item->{$key} );
	# simplest: a scalar value
	if( !$type ){
		print "$prefix$key: $item->{$key}".EOL;
	# if a the key points to an array, the display array items
	} elsif( $type eq 'ARRAY' ){
		print "$prefix$key:".EOL;
		foreach my $it ( @{$item->{$key}} ){
			print "$prefix  $it".EOL;
		}
	} elsif( $type eq 'HASH' ){
		print "$prefix$key:".EOL;
		foreach my $k ( keys %{$item->{$key}} ){
			listWorkloadDetailsRec( $item->{$key}, $k, "$prefix  " );
		}
	} else {
		print "  $key: <object reference>".EOL;
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"services!"			=> \$opt_services,
	"workloads!"		=> \$opt_workloads, 
	"workload=s"		=> \$opt_workload,
	"commands!"			=> \$opt_commands,
	"hidden!"			=> \$opt_hidden )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='true'" );
Mods::Toops::msgVerbose( "found services='$opt_services'" );
Mods::Toops::msgVerbose( "found workloads='".( $opt_workloads ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found workload='$opt_workload'" );
Mods::Toops::msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found hidden='".( $opt_hidden ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listDbms() if $opt_dbms;
	listServices() if $opt_services;
	listWorkloads() if $opt_workloads;
	listWorkloadDetails() if $opt_workload && !$opt_commands;
	listWorkloadCommands() if $opt_workload && $opt_commands;
}

Mods::Toops::ttpExit();
