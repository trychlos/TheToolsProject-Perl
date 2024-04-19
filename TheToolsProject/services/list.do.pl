# @(#) list various services objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]services          list services defined on this machine [${services}]
# @(-) --[no]workloads         list workloads used on this machine [${workloads}]
# @(-) --[no]hidden            also display hidden services or workloads on hidden services [${hidden}]
# @(-) --[no]environment       display the environment to which this machine is attached [${environment}]
# @(-) --service=<name>        display informations about the named service [${service}]
# @(-) --[no]machines          list all the machines which define the named service [${machines}]
# @(-) --type=<type>           restrict list to the machines attached to the specified environment [${type}]
# @(-) --workload=<name>       display informations about the named workload [${workload}]
# @(-) --[no]details           list the tasks details [${details}]
# @(-) --[no]commands          only list the commands for the named workload [${commands}]
#
# @(@) with:
# @(@)   services.pl list -services [-hidden]                       list services defined on the current machine, plus maybe the hidden ones
# @(@)   services.pl list -workloads [-hidden]                      list workloads defined on the current machine, plus maybe the hidden ones
# @(@)   services.pl list -environment                              display the environnement of the current machine
# @(@)   services.pl list -service <name> -machines [-type <env>]   list the machines where the named service is defined, maybe for the typed environment
# @(@)   services.pl list -workload <name> -commands [-hidden]      list the commands attached to the named workload, plus maybe the hidden ones
# @(@)   services.pl list -workload <name> -details [-hidden]       list the tasks details of the named workload, plus maybe the hidden ones
#
# @(@) Displayed lists are sorted in ASCII order, i.e. in [0-9A-Za-z] order.
#
# Copyright (@) 2023-2024 PWI Consulting
#

use Data::Dumper;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Services;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	services => 'no',
	hidden => 'no',
	workloads => 'no',
	workload => '',
	commands => 'no',
	details => 'no',
	service => '',
	environment => 'no',
	type => '',
	machines => 'no'
};

my $opt_services = false;
my $opt_hidden = false;
my $opt_workloads = false;
my $opt_workload = $defaults->{workload};
my $opt_commands = false;
my $opt_details = false;
my $opt_service = $defaults->{service};
my $opt_environment = false;
my $opt_type = $defaults->{type};
my $opt_machines = false;

# the host configuration
my $hostConfig = Mods::Toops::getHostConfig();

# -------------------------------------------------------------------------------------------------
# display the environment for this machine (may be 0 or 1)
sub listEnvironment {
	msgOut( "displaying environment for '$hostConfig->{name}' machine..." );
	my $env = $hostConfig->{Environment}{type};
	my $count = 0;
	if( !$env ){
		msgOut( "no environment registered with this machine" );
	} else {
		print " $env".EOL; 
		$count += 1;
	}
	msgOut("$count found defined environment" );
}

# -------------------------------------------------------------------------------------------------
# display the machines which provides the service, maybe in a specified environment type
sub listServiceMachines {
	if( $opt_type ){
		msgOut( "displaying machines which provide '$opt_service' service in '$opt_type' environment..." );
	} else {
		msgOut( "displaying machines which provide '$opt_service' service..." );
	}
	my $count = 0;
	my @hosts = Mods::Toops::getDefinedHosts();
	msgVerbose( "found ".scalar @hosts." host(s)" );
	foreach my $host ( @hosts ){
		msgVerbose( "examining '$host'" );
		my $hostConfig = Mods::Toops::getHostConfig( $host );
		if(( !$opt_type || $hostConfig->{Environment}{type} eq $opt_type ) && exists( $hostConfig->{Services}{$opt_service} )){
			print "  $hostConfig->{Environment}{type}: $host".EOL;
			$count += 1;
		}
	}
	msgOut("$count found machine(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all the defined services on this host
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	msgOut( "displaying services defined on $hostConfig->{name}..." );
	my @list = Mods::Services::getDefinedServices( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	msgOut( scalar @list." found defined service(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all the workloads used by a service on this host with names sorted in ascii order
sub listWorkloads {
	msgOut( "displaying workloads used on $hostConfig->{name}..." );
	my @list = Mods::Services::getUsedWorkloads( $hostConfig, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	msgOut( scalar @list." found used workload(s)" );
}

# -------------------------------------------------------------------------------------------------
# list all (but only) the commands in this workload
# the commands are listed in the order of their service name
sub listWorkloadCommands {
	msgOut( "displaying workload commands defined in $hostConfig->{name}\\$opt_workload..." );
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
	msgOut( "$count found defined command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the detailed tasks for the specified workload
# They are displayed in the order of their service name
sub listWorkloadDetails {
	msgOut( "displaying detailed workload tasks defined in $hostConfig->{name}\\$opt_workload..." );
	my @list = Mods::Services::getDefinedWorktasks( $hostConfig, $opt_workload, { hidden => $opt_hidden });
	foreach my $it ( @list ){
		printWorkloadTask( $it );
	}
	msgOut( scalar @list." found defined task(s)" );
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
	"services!"			=> \$opt_services,
	"hidden!"			=> \$opt_hidden,
	"workloads!"		=> \$opt_workloads, 
	"workload=s"		=> \$opt_workload,
	"commands!"			=> \$opt_commands,
	"details!"			=> \$opt_details,
	"service=s"			=> \$opt_service,
	"environment!"		=> \$opt_environment,
	"type=s"			=> \$opt_type,
	"machines!"			=> \$opt_machines )){

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
msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );
msgVerbose( "found hidden='".( $opt_hidden ? 'true':'false' )."'" );
msgVerbose( "found workloads='".( $opt_workloads ? 'true':'false' )."'" );
msgVerbose( "found workload='$opt_workload'" );
msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
msgVerbose( "found details='".( $opt_details ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found environment='".( $opt_environment ? 'true':'false' )."'" );
msgVerbose( "found type='$opt_type'" );
msgVerbose( "found machines='".( $opt_machines ? 'true':'false' )."'" );

if( $opt_service && !$opt_machines ){
	msgWarn( "a service is named, but without any requested information" );
}
if( $opt_machines && !$opt_service ){
	msgWarn( "request a machines list without having specified a service" );
}
if( $opt_workload && !$opt_commands && !$opt_details ){
	msgWarn( "a workload is named, but without any requested information" );
}

if( !ttpErrs()){
	listEnvironment() if $opt_environment;
	listServiceMachines() if $opt_service && $opt_machines;
	listServices() if $opt_services;
	listWorkloadCommands() if $opt_workload && $opt_commands;
	listWorkloadDetails() if $opt_workload && $opt_details;
	listWorkloads() if $opt_workloads;
}

ttpExit();
