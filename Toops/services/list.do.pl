# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]dbms              list defined DBMS instances [${dbms}]
# @(-) --[no]services          list defined services [${services}]
# @(-) --[no]hidden            also display hidden services [${hidden}]
# @(-) --[no]workloads         list used workloads [${workloads}]
# @(-) --workload=<name>       display the detailed tasks for the named workload [${workload}]
# @(-) --[no]commands          display only the commands for the named workload [${commands}]
#
# @(@) Displayed lists are sorted in ASCII order, i.e. in [0-9A-Za-z] order.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants;
use Mods::Services;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	dbms => 'no',
	services => 'no',
	hidden => 'no',
	workloads => 'no',
	workload => '',
	commands => 'no'
};

my $opt_dbms = false;
my $opt_services = false;
my $opt_hidden = false;
my $opt_workloads = false;
my $opt_workload = $defaults->{workload};
my $opt_commands = false;

# -------------------------------------------------------------------------------------------------
# list the defined DBMS instances (which may be not all the running instances)
sub listDbms {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying DBMS instances defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedDBMSInstances( $hostConfig );
	foreach my $it ( @list ){
		print " $it".EOL;
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
# list all the workloads used on this host with names sorted in ascii order
sub listWorkloads {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workloads used on $hostConfig->{name}..." );
	my @list = Mods::Services::getUsedWorkloads( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Toops::msgOut( scalar @list." found used workload(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all (but only) the commands in this workload
# the commands are listed in the order if their service name
sub listWorkloadCommands {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying workload commands defined in $hostConfig->{name}\\$opt_workload..." );
	my @list = Mods::Services::getDefinedWorktasks( $hostConfig, $opt_workload, { hidden => $opt_hidden });
	my $count = 0;
	foreach my $it ( @list ){
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
# They are displayed in the order of their service name
sub listWorkloadDetails {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "displaying detailed workload tasks defined in $hostConfig->{name}\\$opt_workload..." );
	my @list = Mods::Services::getDefinedWorktasks( $hostConfig, $opt_workload, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		printWorkloadTask( $it );
	}
	Mods::Toops::msgOut( scalar @list." found defined task(s)" );
}

# -------------------------------------------------------------------------------------------------
# print the detail of a task
# - begin with preferably a name, defaulting to a label, defaulting to 'unnamed'
sub printWorkloadTask {
	my ( $task ) = @_;
	# if we have a name or label, make it the first line
	if( exists( $task->{name} )){
		print "+ $task->{name}".EOL;
	} elsif( exists( $task->{label} )){
		print "+ $task->{label}".EOL;
	} else {
		print "+ (unnamed)".EOL;
	}
	# if we have both a name and an label, print the label now
	if( exists( $task->{name} ) && exists( $task->{label} )){
		print "  $task->{label}".EOL;
	}
	# print other keys
	# we manage one level array/hash to be able to display at least commands (sorted to have a predictable display)
	foreach my $key ( sort keys %{$task} ){
		if( $key ne 'name' && $key ne 'label' ){
			printWorkloadTaskData( $key, $task->{$key}, { prefix => "  " });
		}
	}
}

# -------------------------------------------------------------------------------------------------
# recursively print arrays/hashes
# item is a hash and we want print the value associated with the key in the item hash
sub printWorkloadTaskData {
	my ( $key, $value, $recData ) = @_;
	my $type = ref( $value );
	my $displayKey = true;
	$displayKey = $recData->{displayKey} if exists $recData->{displayKey};
	# simplest: a scalar value
	if( !$type ){
		if( $displayKey ){
			print "$recData->{prefix}$key: $value".EOL;
		} else {
			print "$recData->{prefix}$value".EOL;
		}
	# if value is an array, then display key and recurse on array items (do not re-display key)
	} elsif( $type eq 'ARRAY' ){
		print "$recData->{prefix}$key:".EOL;
		foreach my $it ( @{$value} ){
			printWorkloadTaskData( $key, $it, { prefix => "$recData->{prefix}  ", displayKey => false });
		}
	} elsif( $type eq 'HASH' ){
		print "$recData->{prefix}$key:".EOL;
		foreach my $k ( keys %{$value} ){
			printWorkloadTaskData( $k, $value->{$k}, { prefix => "$recData->{prefix}  " });
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
	"dbms!"				=> \$opt_dbms,
	"services!"			=> \$opt_services,
	"hidden!"			=> \$opt_hidden,
	"workloads!"		=> \$opt_workloads, 
	"workload=s"		=> \$opt_workload,
	"commands!"			=> \$opt_commands )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dbms='".( $opt_dbms ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found hidden='".( $opt_hidden ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found workloads='".( $opt_workloads ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found workload='$opt_workload'" );
Mods::Toops::msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );

if( !Mods::Toops::errs()){
	listDbms() if $opt_dbms;
	listServices() if $opt_services;
	listWorkloads() if $opt_workloads;
	listWorkloadDetails() if $opt_workload && !$opt_commands;
	listWorkloadCommands() if $opt_workload && $opt_commands;
}

Mods::Toops::ttpExit();
