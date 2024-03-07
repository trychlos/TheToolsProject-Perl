# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]dbms              list defined DBMS instances [${dbms}]
# @(-) --[no]services          list defined services [${services}]
# @(-) --[no]hidden            also display hidden services [${hidden}]
# @(-) --[no]workloads         list used workloads [${workloads}]
# @(-) --workload=<name>       display the detailed tasks for the named workload [${workload}]
# @(-) --[no]commands          display only the commands for the named workload [${commands}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --[no]databases         display the list of databases defined in the service [${databases}]
# @(-) --[no]instance          display the relevant DBMS instance for this service [${instance}]
#
# @(@) Displayed lists are sorted in ASCII order, i.e. in [0-9A-Za-z] order.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Services;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	dbms => 'no',
	services => 'no',
	hidden => 'no',
	workloads => 'no',
	workload => '',
	commands => 'no',
	service => '',
	databases => 'no',
	instance => 'no'
};

my $opt_dbms = false;
my $opt_services = false;
my $opt_hidden = false;
my $opt_workloads = false;
my $opt_workload = $defaults->{workload};
my $opt_commands = false;
my $opt_service = $defaults->{service};
my $opt_databases = false;
my $opt_instance = false;

# the host configuration
my $hostConfig = Mods::Toops::getHostConfig();

# -------------------------------------------------------------------------------------------------
# list the defined DBMS instances (which may be not all the running instances)
sub listDbms {
	Mods::Message::msgOut( "displaying DBMS instances defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedDBMSInstances( $hostConfig );
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Message::msgOut( scalar @list." found defined DBMS instance(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the databases registered with a service
sub listServiceDatabases {
	Mods::Message::msgOut( "displaying databases registered with on '$hostConfig->{name}\\$opt_service' service..." );
	my $instance = $hostConfig->{Services}{$opt_service}{instance};
	my $databases = $hostConfig->{Services}{$opt_service}{databases};
	my $count = 0;
	if( !$instance ){
		Mods::Message::msgOut( "no instance registered with this service (databases may be present, but are ignored)" );
	} else {
		print "+ instance: $instance".EOL; 
		foreach my $db ( @{$databases} ){
			print "  databases:".EOL if !$count;
			print "  - $db".EOL;
			$count += 1;
		}
	}
	Mods::Message::msgOut("$count found defined databases(s)" );
}

# -------------------------------------------------------------------------------------------------
# display the DBMS instance for a service
sub listServiceInstance {
	Mods::Message::msgOut( "displaying instance registered on '$hostConfig->{name}\\$opt_service' service..." );
	my $instance = $hostConfig->{Services}{$opt_service}{instance};
	my $count = 0;
	if( !$instance ){
		Mods::Message::msgOut( "no instance registered with this service (databases may be present, but are ignored)" );
	} else {
		print "+ instance: $instance".EOL; 
		$count += 1;
	}
	Mods::Message::msgOut("$count found defined instance" );
}

# -------------------------------------------------------------------------------------------------
# list all the defined services on this host
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	Mods::Message::msgOut( "displaying services defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedServices( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Message::msgOut( scalar @list." found defined service(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all the workloads used on this host with names sorted in ascii order
sub listWorkloads {
	Mods::Message::msgOut( "displaying workloads used on $hostConfig->{name}..." );
	my @list = Mods::Services::getUsedWorkloads( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	Mods::Message::msgOut( scalar @list." found used workload(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all (but only) the commands in this workload
# the commands are listed in the order if their service name
sub listWorkloadCommands {
	Mods::Message::msgOut( "displaying workload commands defined in $hostConfig->{name}\\$opt_workload..." );
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
	Mods::Message::msgOut( "$count found defined command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the detailed tasks for the specified workload
# They are displayed in the order of their service name
sub listWorkloadDetails {
	Mods::Message::msgOut( "displaying detailed workload tasks defined in $hostConfig->{name}\\$opt_workload..." );
	my @list = Mods::Services::getDefinedWorktasks( $hostConfig, $opt_workload, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		printWorkloadTask( $it );
	}
	Mods::Message::msgOut( scalar @list." found defined task(s)" );
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
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"dbms!"				=> \$opt_dbms,
	"services!"			=> \$opt_services,
	"hidden!"			=> \$opt_hidden,
	"workloads!"		=> \$opt_workloads, 
	"workload=s"		=> \$opt_workload,
	"commands!"			=> \$opt_commands, 
	"service=s"			=> \$opt_service,
	"databases!"		=> \$opt_databases,
	"instance!"			=> \$opt_instance )){

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
Mods::Message::msgVerbose( "found dbms='".( $opt_dbms ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found hidden='".( $opt_hidden ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found workloads='".( $opt_workloads ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found workload='$opt_workload'" );
Mods::Message::msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found service='$opt_service'" );
Mods::Message::msgVerbose( "found databases='".( $opt_databases ? 'true':'false' )."'" );
Mods::Message::msgVerbose( "found instance='".( $opt_instance ? 'true':'false' )."'" );

if( $opt_service && !$opt_databases && !$opt_instance ){
	Mods::Message::msgWarn( "a service is specified, but without any requested information" );
}

if( !Mods::Toops::errs()){
	listDbms() if $opt_dbms;
	listServices() if $opt_services;
	listWorkloads() if $opt_workloads;
	listWorkloadDetails() if $opt_workload && !$opt_commands;
	listWorkloadCommands() if $opt_workload && $opt_commands;
	listServiceDatabases() if $opt_service && $opt_databases;
	listServiceInstance() if $opt_service && $opt_instance;
}

Mods::Toops::ttpExit();
