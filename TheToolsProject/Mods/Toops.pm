# Copyright (@) 2023-2024 PWI Consulting

package Mods::Toops;

use strict;
use warnings;

use Config;
use Data::Dumper;
use Data::UUID;
use Devel::StackTrace;
use File::Copy qw( copy move );
use File::Copy::Recursive qw( dircopy );
use File::Path qw( make_path remove_tree );
use File::Spec;
use Getopt::Long;
use JSON;
use Path::Tiny qw( path );
use Sys::Hostname qw( hostname );
use Test::Deep;
use Time::Moment;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::MessageLevel qw( :all );
use Mods::Path;

# autoflush STDOUT
$| = 1;

# store here our Toops variables
our $TTPVars = {
	Toops => {
		# defaults which depend of the host OS
		defaults => {
			darwin => {
				tempDir => '/tmp'
			},
			linux => {
				tempDir => '/tmp'
			},
			MSWin32 => {
				tempDir => 'C:\\Temp'
			}
		},
		# reserved words: the commands must be named outside of this array
		#  either because they are folders of the Toops installation tree
		#  or because they are first level key in TTPVars (thus preventing to have a 'command' object at this first level)
		ReservedWords => [
			'bin',
			'config',
			'dyn',
			'Mods',
			'run',
			'Toops'
		],
		# main configuration keys
		ConfigKeys => [
			'toops',
			'site',
			'host'
		],
		# some internally used constants
		commentPreUsage => '^# @\(#\) ',
		commentPostUsage => '^# @\(@\) ',
		commentUsage => '^# @\(-\) ',
		verbSufix => '.do.pl',
		verbSed => '\.do\.pl',
		# some runtime constants
		stackOnErr => false
	},
	# a key reserved for the storage of toops+site+host raw json configuration files
	json => undef,
	# initialize some run variables
	run => {
		exitCode => 0,
		help => false,
		verbose => false,
		dummy => false,
		colored => true
	}
};

# -------------------------------------------------------------------------------------------------
# Execute a command dependant of the running OS.
# This is expected to be configured in TOOPS.json as TOOPS => {<key>} => {command}
# where command may have some keywords to be remplaced before execution
# (E):
# argument is a hash with following keys:
# - command: the command to be evaluated and executed, may be undef
# - macros: a hash of the macros to be replaced where:
#   > key is the macro name, must be labeled in the toops.json as '<macro>' (i.e. between angle brackets)
#   > value is the value to be replaced
# (S):
# return a hash with following keys:
# - evaluated: the evaluated command after macros replacements
# - return: original exit code of the command
# - result: true|false
sub commandByOs {
	my ( $args ) = @_;
	my $result = {};
	$result->{command} = $args->{command};
	$result->{result} = false;
	msgVerbose( "Toops::commandByOs() evaluating and executing command='".( $args->{command} || '(undef)' )."'" );
	if( defined $args->{command} ){
		$result->{evaluated} = $args->{command};
		foreach my $key ( keys %{$args->{macros}} ){
			$result->{evaluated} =~ s/<$key>/$args->{macros}{$key}/;
		}
		msgVerbose( "Toops::commandByOs() evaluated to '$result->{evaluated}'" );
		msgDummy( $result->{evaluated} );
		if( !wantsDummy()){
			my $out = `$result->{evaluated}`;
			print $out;
			msgLog( $out );
			# https://www.perlmonks.org/?node_id=81640
			# Thus, the exit value of the subprocess is actually ($? >> 8), and $? & 127 gives which signal, if any, the
			# process died from, and $? & 128 reports whether there was a core dump.
			# https://ss64.com/nt/robocopy-exit.html
			my $res = $?;
			$result->{result} = ( $res == 0 ) ? true : false;
			msgVerbose( "Toops::commandByOs() return_code=$res firstly interpreted as result=$result->{result}" );
			if( $args->{command} =~ /robocopy/i ){
				$res = ( $res >> 8 );
				$result->{result} = ( $res <= 7 ) ? true : false;
				msgVerbose( "Toops::commandByOs() robocopy specific interpretation res=$res result=$result->{result}" );
			}
		} else {
			$result->{result} = true;
		}
	}
	msgVerbose( "Toops::commandByOs() result=$result->{result}" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# copy a directory and its content from a source to a target
# this is a design decision to make this recursive copy file by file in order to have full logs
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to move big files to network storage
# return true|false
sub copyDir {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::copyDir() entering with source='$source' target='$target'" );
	if( ! -d $source ){
		msgErr( "$source: source directory doesn't exist" );
		return false;
	}
	my $cmdres = commandByOs({
		command => $TTPVars->{config}{toops}{copyDir}{byOS}{$Config{osname}}{command},
		macros => {
			SOURCE => $source,
			TARGET => $target
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		msgVerbose( "Toops::copyDir() commandByOs() result=$result" );
	} else {
		msgDummy( "dircopy( $source, $target )" );
		if( !wantsDummy()){
			# https://metacpan.org/pod/File::Copy::Recursive
			# This function returns true or false: for true in scalar context it returns the number of files and directories copied,
			# whereas in list context it returns the number of files and directories, number of directories only, depth level traversed.
			my $res = dircopy( $source, $target );
			$result = $res ? true : false;
			msgVerbose( "Toops::copyDir() dircopy() res=$res result=$result" );
		}
	}
	msgVerbose( "Toops::copyDir() returns result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# copy a file from a source to a target
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to copy big files to network storage
# (I):
# - source: the source volume, directory and filename
# - target :the target volume and directory
# (O):
# return true|false
sub copyFile {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::copyFile() entering with source='$source' target='$target'" );
	# isolate the file from the source directory path
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $source );
	my $srcpath = File::Spec->catpath( $vol, $dirs );
	my $cmdres = commandByOs({
		command => $TTPVars->{config}{toops}{copyFile}{byOS}{$Config{osname}}{command},
		macros => {
			SOURCE => $srcpath,
			TARGET => $target,
			FILE => $file
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		msgVerbose( "Toops::copyFile() commandByOs() result=$result" );
	} else {
		msgDummy( "copy( $source, $target )" );
		if( !wantsDummy()){
			# https://metacpan.org/pod/File::Copy
			# This function returns true or false
			$result = copy( $source, $target );
			if( $result ){
				msgVerbose( "Toops::copyFile() result=true" );
			} else {
				msgErr( "Toops::copyFile() $!" );
			}
		}
	}
	msgVerbose( "Toops::copyFile() returns result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Dump the internal variables
sub dump {
	foreach my $key ( keys %{$TTPVars} ){
		Mods::Toops::msgVerbose( "$key='$TTPVars->{$key}'", { verbose => true, withLog => true });
	}
}

# -------------------------------------------------------------------------------------------------
# is there any error
#  exit code may be seen as an error counter as it is incremented by msgErr
sub errs {
	return $TTPVars->{run}{exitCode};
}

# -------------------------------------------------------------------------------------------------
# recursively interpret the provided data for variables and computings
#  and restart until all references have been replaced
sub evaluate {
	my ( $value ) = @_;
	my %prev = ();
	my $result = _evaluateRec( $value );
	while( !eq_deeply( $result, \%prev )){
		%prev = %{$result};
		$result = _evaluateRec( $result );
	}
	return $result;
}

sub _evaluateRec {
	my ( $value ) = @_;
	my $result = '';
	my $type = ref( $value );
	if( !$type ){
		$result = _evaluateScalar( $value );
	} elsif( $type eq 'ARRAY' ){
		$result = [];
		foreach my $it ( @{$value} ){
			push( @{$result}, _evaluateRec( $it ));
		}
	} elsif( $type eq 'HASH' ){
		$result = {};
		foreach my $key ( keys %{$value} ){
			$result->{$key} = _evaluateRec( $value->{$key} );
		}
	} else {
		$result = $value;
	}
	return $result;
}

sub _evaluateScalar {
	my ( $value ) = @_;
	my $type = ref( $value );
	my $evaluate = true;
	if( $type ){
		msgErr( "scalar expected, but '$type' found" );
		$evaluate = false;
	}
	my $result = $value || '';
	if( $evaluate ){
		# this weird code to let us manage some level of pseudo recursivity
		$result =~ s/\[eval:([^\]]+)\]/_evaluatePrint( $1 )/eg;
		$result =~ s/\[_eval:/[eval:/g;
		$result =~ s/\[__eval:/[_eval:/g;
		$result =~ s/\[___eval:/[__eval:/g;
		$result =~ s/\[____eval:/[___eval:/g;
		$result =~ s/\[_____eval:/[____eval:/g;
	}
	return $result;
}

sub _evaluatePrint {
	my ( $value ) = @_;
	my $result = eval $value;
	# we cannot really emit a warning here as it is possible that we are in the way of resolving
	# a still-undefined value. so have to wait until the end to resolve all values, but too late
	# to emit a warning ?
	#msgWarn( "something is wrong with '$value' as evaluation result is undefined" ) if !defined $result;
	$result = $result ||'(undef)';
	#print "value='$value' result='$result'".EOL;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# append a record to our daily executions reports
# send a MQTT message if Toops is configured for
# (I):
# - the data provided to be recorded
# - optional options hash with following keys:
#   > topic: an array reference with a list of report keys to be appended to the topic, defaulting to none
#   > retain: whether to retain the message, defaulting to false
# This function automatically appends:
# - hostname
# - start timestamp
# - end timestamp
# - return code
# - full run command
sub execReportByCommand {
	my ( $data, $opts ) = @_;
	$opts //= {};
	# add some auto elements
	$data->{cmdline} = "$0 ".join( ' ', @{$TTPVars->{run}{command}{args}} );
	$data->{command} = $TTPVars->{run}{command}{basename};
	$data->{verb} = $TTPVars->{run}{verb}{name};
	$data->{host} = uc hostname;
	$data->{code} = $TTPVars->{run}{exitCode};
	$data->{started} = $TTPVars->{run}{command}{started}->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{dummy} = $TTPVars->{run}{dummy};
	execReportToFile( $data, $opts );
	execReportToMqtt( $data, $opts );
}

# -------------------------------------------------------------------------------------------------
# append a record to our daily executions reports dir if Toops is configured for
# please note that having the json filenames ordered both by name and by date is a design decision - do not change
# (I):
# - the data to be written
sub execReportToFile {
	my ( $report, $opts ) = @_;
	if( exists( $TTPVars->{config}{toops}{executionReport}{withFile} )){
		msgVerbose( "execReportToFile() TTPVars->{config}{toops}{executionReport}{withFile}=$TTPVars->{config}{toops}{executionReport}{withFile}" );
	} else {
		msgVerbose( "execReportToFile() TTPVars->{config}{toops}{executionReport}{withFile} is undef" );
	}
	if( $TTPVars->{config}{toops}{executionReport}{withFile} ){
		my $path = File::Spec->catdir( Mods::Path::execReportsDir(), Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N.json' ));
		jsonWrite( $report, $path );
	}
}

# -------------------------------------------------------------------------------------------------
# send an execution report on the MQTT bus if Toops is configured for
# (I):
# - the data to be written
sub execReportToMqtt {
	my ( $report, $opts ) = @_;
	if( exists( $TTPVars->{config}{toops}{executionReport}{withMqtt} )){
		msgVerbose( "execReportToMqtt() TTPVars->{config}{toops}{executionReport}{withMqtt}=$TTPVars->{config}{toops}{executionReport}{withMqtt}" );
	} else {
		msgVerbose( "execReportToMqtt() TTPVars->{config}{toops}{executionReport}{withMqtt} is undef" );
	}
	if( $TTPVars->{config}{toops}{executionReport}{withMqtt} ){
		my $topic = uc hostname;
		delete $report->{host} if exists $report->{host};
		$topic .= "/executionReport";
		if( $report->{command} ){
			$topic .= "/$report->{command}";
			delete $report->{command};
		}
		if( $report->{verb} ){
			$topic .= "/$report->{verb}";
			delete $report->{verb};
		}
		if( $opts->{topic} && ref( $opts->{topic} ) eq 'ARRAY' ){
			foreach my $it ( @{$opts->{topic}} ){
				if( exists( $report->{$it} )){
					$topic .= "/$report->{$it}";
					delete $report->{$it};
				}
			}
		}
		my $json = JSON->new;
		my $message = $json->encode( $report );
		my $verbose = '';
		$verbose = "-verbose" if $TTPVars->{run}{verbose};
		my $retain = '';
		$retain = '-retain' if $opts->{retain};
		my $stdout = `mqtt.pl publish -topic $topic -payload "\"$message\"" $verbose $retain`;
		print $stdout;
	}
}

# -------------------------------------------------------------------------------------------------
# returns array with the pathname of the available commands
# if the user has added a tree of its own besides of Toops, it should have set a TTP_ROOT environment
# variable - else just stay in this current tree...
sub getAvailableCommands {
	# compute a TTP_ROOT array of directories
	my @roots = ();
	if( $ENV{TTP_ROOT} ){
		@roots = split( ':', $ENV{TTP_ROOT} );
	} else {
		push( @roots, $TTPVars->{run}{command}{directory} );
	}
	my @commands = glob( File::Spec->catdir( $TTPVars->{run}{command}{directory}, "*.pl" ));
	return @commands;
}

# -------------------------------------------------------------------------------------------------
# returns the default temp directory for the running OS
sub getDefaultTempDir {
	return $TTPVars->{Toops}{defaults}{$Config{osname}}{tempDir};
}

# -------------------------------------------------------------------------------------------------
# read and evaluate the host configuration
# if host is not specified, then return the configuration of the current host from TTPVars
# send an error message if the top key of the read json is not the requested host name
# eat this top key, adding a 'name' key to the data with the canonical (uppercase)  host name
# (I):
# - an optional hostname
# - an optional options hash with following keys:
#   > withEvaluate: default to true
# (O):
# - returns a reference to the (evaluated) host configuration with its new 'name' key
sub getHostConfig {
	my ( $host, $opts ) = @_;
	if( !$host ){
		return $TTPVars->{config}{host};
	}
	$opts //= {};
	my $hash = hostConfigRead( $host );
	if( $hash ){
		my $withEvaluate = true;
		$withEvaluate = $opts->{withEvaluate} if exists $opts->{withEvaluate};
		if( $withEvaluate ){
			$hash = evaluate( $hash );
		}
	}
	return $hash;
}

# -------------------------------------------------------------------------------------------------
# returns the list of JSON configuration full pathnames for defined hosts (including this one)
sub getJsonHosts {
	my @hosts = glob( Mods::Path::hostsConfigurationsDir()."/*.json" );
	return @hosts;
}

# -------------------------------------------------------------------------------------------------
# Interpret the command-line options
# Deal here with -help and -verbose
# args is a ref to an array of hashes with following keys:
# - key: the option name
# - help: a short help message
# - opt: the string to be appended to the option to be passed to GetOptions::Long
# - var: the reference to the variable which will hold the value
# - def: the displayed default value
sub getOptions {
	Mods::Toops::msgErr( "Mods::Toops::getOptions() is just a placeholder for now. Please use standard GetOptions()." );
}

=pod
# -------------------------------------------------------------------------------------------------
# Interpret the command-line options
# Deal here with -help and -verbose
# args is a ref to an array of hashes with following keys:
# - key: the option name
# - help: a short help message
# - opt: the string to be appended to the option to be passed to GetOptions::Long
# - var: the reference to the variable which will hold the value
# - def: the displayed default value
sub getOptions {
	my $parms = shift;
	print "getOoptions()".EOL;
	my $args = getOptionsPrepend( $parms );
	my $optargs = getOptionsToOpts( $args );
	#print Dumper( $optargs );
	print "calling GetOptions()..".EOL;
	if( !myGetOptions( @{$optargs} )){
		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		#$TTPVars->{exitCode} += 1;
		Mods::Toops::ttpExit();
	}
	print "return from GetOptions()".EOL;
	if( !scalar @{$TTPVars->{verb_args}} ){
		$TTPVars->{help} = true;
	}
	if( $TTPVars->{help} ){
		Mods::Toops::helpVerb();
		Mods::Toops::ttpExit();
	}
	Mods::Toops::msgVerbose( "found verbose='true'" );
}

# -------------------------------------------------------------------------------------------------
# Append our own options to the list of verb options
sub getOptionsPrepend {
	my $parms = shift;
	my $args = [
		{
			key	 => 'help',
			help => 'print this message, and exit',
			opt	 => '!',
			var  => \$TTPVars->{help},
			def  => "no"
		},
		{
			key	 => 'verbose',
			help => 'run verbosely',
			opt	 => '!',
			var  => \$TTPVars->{verbose},
			def  => "no"
		}
	];
	$TTPVars->{help} = false;
	$TTPVars->{verbose} = false;
	return [ @{$args}, @{$parms} ];
}

# -------------------------------------------------------------------------------------------------
# convert the Toops options array to the GetOptions one
sub getOptionsToOpts {
	my $parms = shift;
	my $args = [];
	foreach my $opt ( @{$parms} ){
		print Dumper( $opt );
		push( @{$args}, [ $opt->{key}.$opt->{opt},  $opt->{var} ]);
	}
	print Dumper( $args );
	return $args;
}
=cut

# -------------------------------------------------------------------------------------------------
# returns a random identifier
sub getRandom {
	my $ug = new Data::UUID;
	my $uuid = lc $ug->create_str();
	$uuid =~ s/-//g;
	return $uuid;
}

# -------------------------------------------------------------------------------------------------
# returns a new unique temp filename
sub getTempFileName {
	my $fname = $TTPVars->{run}{command}{name}.'-'.$TTPVars->{run}{verb}{name};
	my $random = getRandom();
	my $tempfname = File::Spec->catdir( $TTPVars->{run}{logsDir}, "$fname-$random.tmp" );
	msgVerbose( "getTempFileName() tempfname='$tempfname'" );
	return $tempfname;
}

# -------------------------------------------------------------------------------------------------
# returns the available verbs for the current command
sub getVerbs {
	my @verbs = glob( File::Spec->catdir( $TTPVars->{run}{command}{verbsDir}, "*".$TTPVars->{Toops}{verbSufix} ));
	return @verbs;
}

# -------------------------------------------------------------------------------------------------
# greps a file with a regex
# (E):
# - the filename to be grep-ed
# - the regex to apply
# - an optional options hash with following keys:
#   > warnIfNone defaulting to true
#   > warnIfSeveral defaulting to true
#   > replaceRegex defaulting to true
#   > replaceValue, defaulting to empty
# always returns an array, maybe empty
sub grepFileByRegex {
	my ( $filename, $regex, $opts ) = @_;
	$opts //= {};
	local $/ = "\r\n";
	my @content = path( $filename )->lines_utf8;
	chomp @content;
	my @grepped = grep( /$regex/, @content );
	# warn if grepped is empty ?
	my $warnIfNone = true;
	$warnIfNone = $opts->{warnIfNone} if exists $opts->{warnIfNone};
	if( scalar @grepped == 0 ){
		Mods::Toops::msgWarn( "'$filename' doesn't have any line with the searched content ('$regex')." ) if $warnIfNone;
	} else {
		# warn if there are several lines in the grepped result ?
		my $warnIfSeveral = true;
		$warnIfSeveral = $opts->{warnIfSeveral} if exists $opts->{warnIfSeveral};
		if( scalar @grepped > 1 ){
			Mods::Toops::msgWarn( "'$filename' has more than one line with the searched content ('$regex')." ) if $warnIfSeveral;
		}
	}
	# replace the regex, and, if true, with what ?
	my $replaceRegex = true;
	$replaceRegex = $opts->{replaceRegex} if exists $opts->{replaceRegex};
	if( $replaceRegex ){
		my @temp = ();
		my $replaceValue = '';
		$replaceValue = $opts->{replaceValue} if exists $opts->{replaceValue};
		foreach my $line ( @grepped ){
			$line =~ s/$regex/$replaceValue/;
			push( @temp, $line );
		}
		@grepped = @temp;
	}
	return @grepped;
}

# -------------------------------------------------------------------------------------------------
# Display the command help as:
# - a one-liner from the command itself
# - and the one-liner help of each available verb
sub helpCommand {
	msgVerbose( "helpCommand()" );
	# display the command one-line help
	Mods::Toops::helpCommandOneline( $TTPVars->{run}{command}{path} );
	# display each verb one-line help
	my @verbs = Mods::Toops::getVerbs();
	my $verbsHelp = {};
	foreach my $it ( @verbs ){
		my @fullHelp = Mods::Toops::grepFileByRegex( $it, $TTPVars->{Toops}{commentPreUsage}, { warnIfSeveral => false });
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $it );
		my $verb = $file;
		$verb =~ s/$TTPVars->{Toops}{verbSed}$//;
		$verbsHelp->{$verb} = $fullHelp[0];
	}
	# verbs being alpha sorted
	@verbs = keys %{$verbsHelp};
	my @sorted = sort @verbs;
	foreach my $it ( @sorted ){
		print "  $it: $verbsHelp->{$it}".EOL;
	}
}

# -------------------------------------------------------------------------------------------------
# Display the command one-liner help help
# (E):
# - the full path to the command
# - an optional options hash with following keys:
#   > prefix: the line prefix, defaulting to ''
sub helpCommandOneline {
	my ( $command_path, $opts ) = @_;
	$opts //= {};
	my $prefix = '';
	$prefix = $opts->{prefix} if exists( $opts->{prefix} );
	my ( $vol, $dirs, $bname ) = File::Spec->splitpath( $command_path );
	my @commandHelp = Mods::Toops::grepFileByRegex( $command_path, $TTPVars->{Toops}{commentPreUsage} );
	print "$prefix$bname: $commandHelp[0]".EOL;
}

# -------------------------------------------------------------------------------------------------
# Display the full verb help
# - the one-liner help of the command
# - the full help of the verb as:
#   > a pre-usage help
#   > the usage of the verb
#   > a post-usage help
# (I):
# - a hash which contains default values
# - an optional options hash with following keys:
#   > usage: a reference to display available options
sub helpVerb {
	msgVerbose( "helpVerb()" );
	my ( $defaults, $opts ) = @_;
	$opts //= {};
	# display the command one-line help
	Mods::Toops::helpCommandOneline( $TTPVars->{run}{command}{path} );
	# verb pre-usage
	my @verbHelp = Mods::Toops::grepFileByRegex( $TTPVars->{run}{verb}{path}, $TTPVars->{Toops}{commentPreUsage}, { warnIfSeveral => false });
	my $verbInline = '';
	if( scalar @verbHelp ){
		$verbInline = shift @verbHelp;
	}
	print "  $TTPVars->{run}{verb}{name}: $verbInline".EOL;
	foreach my $line ( @verbHelp ){
		print "    $line".EOL;
	}
	# verb usage
	if( $opts->{usage} ){
		@verbHelp = @{$opts->{usage}->()};
	} else {
		@verbHelp = Mods::Toops::grepFileByRegex( $TTPVars->{run}{verb}{path}, $TTPVars->{Toops}{commentUsage}, { warnIfSeveral => false });
	}
	if( scalar @verbHelp ){
		print "    Usage: $TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} [options]".EOL;
		print "    where available options are:".EOL;
		foreach my $line ( @verbHelp ){
			$line =~ s/\$\{?(\w+)}?/$defaults->{$1}/e;
			print "      $line".EOL;
		}
	}
	# verb post-usage
	@verbHelp = Mods::Toops::grepFileByRegex( $TTPVars->{run}{verb}{path}, $TTPVars->{Toops}{commentPostUsage}, { warnIfNone => false, warnIfSeveral => false });
	if( scalar @verbHelp ){
		foreach my $line ( @verbHelp ){
			print "    $line".EOL;
		}
	}
}

# -------------------------------------------------------------------------------------------------
# Returns the help line for the standard options
sub helpVerbStandardOptions {
	my @help = (
		"--[no]help              print this message, and exit [no]",
		"--[no]verbose           run verbosely [no]",
		"--[no]colored           color the output depending of the message level [yes]",
		"--[no]dummy             dummy run (ignored here) [no]"
	);
	return \@help;
}

# -------------------------------------------------------------------------------------------------
# read the host configuration without evaluation but checks that we have the correct top key
# (I):
# - the hostname
# (O):
# - returns the data under the toplevel key (which is expected to be the hostname)
#   with a new 'name' key which contains this same hostname
# or undef in case of an error
sub hostConfigRead {
	my ( $host ) = @_;
	my $result = undef;
	if( !$host ){
		msgErr( "hostConfigRead() hostname expected" );
	} else {
		my $hash = jsonRead( Mods::Path::hostConfigurationPath( $host ));
		if( $hash ){
			my $topkey = ( keys %{$hash} )[0];
			if( $topkey ne $host ){
				msgErr( "expected toplevel key '$host', found '$topkey'" ) ;
			} else {
				$result = $hash->{$topkey};
				$result->{name} = $host;
			}
		}
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Initialize TheToolsProject
# - reading the toops+site and host configuration files and interpreting them before first use
# - initialize the logs internal variables
sub init {
	$TTPVars->{Toops}{json} = jsonRead( Mods::Path::toopsConfigurationPath());
	# make sure the toops+site configuration doesn't have any other key
	# immediately aborting if this is the case
	# accepting anyway 'toops' and 'site'-derived keys (like 'site_comments' for example)
	my @others = ();
	foreach my $key ( keys %{$TTPVars->{Toops}{json}} ){
		push( @others, "'$key'" ) unless index( $key, "toops" )==0 || index( $key, "site" )==0;
	}
	if( scalar @others ){
		print STDERR "Invalid key(s) found in toops.json configuration file: ".join( ', ', @others )."\n";
		print STDERR "Site own keys should be inside 'site' hierarchy\n";
		exit( 1 );
	}
	$TTPVars->{Toops}{json}{host} = hostConfigRead( uc hostname );
	ttpEvaluate();
	msgLog( "executing $0 ".join( ' ', @ARGV ));
}

# -------------------------------------------------------------------------------------------------
# get the machine services configuration as a hash indexed by hostname
#  HostConf::init() is expected to return a hash with a single top key which is the hostname
#  we check and force that here
#  + set the host as a value to be more easily available
sub initHostConfiguration {
=pod
	my $host = uc hostname;
	my $config = getHostConfig( $host, { withEvaluate => false });
	if( $config ){
		# rationale: evaluate() may want take advantage of its own TTPVars config content, so must be set before evaluation
		$TTPVars->{config}{$host} = $config;
		$TTPVars->{config}{$host} = evaluate( $TTPVars->{config}{$host} );
	}
=cut
}

# -------------------------------------------------------------------------------------------------
# Make sure we have a site configuration JSON file and loads and interprets it
sub initSiteConfiguration {
=pod
	my $conf = Mods::Path::toopsConfigurationPath();
	$TTPVars->{config}{site} = jsonRead( $conf );
	# rationale: evaluate() may want take advantage of the TTPVars content, so must be set before evaluation
	$TTPVars->{config}{site} = evaluate( $TTPVars->{config}{site} );
=cut
}

# -------------------------------------------------------------------------------------------------
# Append a JSON element to a file
# (E):
# - the hash to be written into
# - the full path to be created
sub jsonAppend {
	my ( $hash, $path ) = @_;
	msgVerbose( "jsonAppend().. to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	Mods::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	path( $path )->append_utf8( $str.EOL );
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file data
# (E):
# - the full path to the to-be-loaded-and-interpreted json file
sub jsonRead {
	my ( $conf ) = @_;
	msgVerbose( "jsonRead() conf='$conf'" );
	my $result = undef;
	if( $conf && -r $conf ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $conf ) or msgErr( "jsonRead() $conf: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		$result = $json->decode( $content );
	} elsif( $conf ){
		msgErr( "jsonRead() $conf: not found or not readable" );
	} else {
		msgErr( "jsonRead() expects a JSON path to be read" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Write a hash to a JSON file
# (E):
# - the hash to be written into
# - the full path to be created
sub jsonWrite {
	my ( $hash, $path ) = @_;
	msgVerbose( "jsonWrite() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	Mods::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	path( $path )->spew_utf8( $str.EOL );
}

# -------------------------------------------------------------------------------------------------
# (recursively) move a directory and its content from a source to a target
# this is a design decision to make this recursive copy file by file in order to have full logs
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to move big files to network storage
sub moveDir {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::moveDir() source='$source' target='$target'" );
	if( ! -d $source ){
		msgWarn( "$source: directory doesn't exist" );
		return true;
	}
	my $cmdres = commandByOs({
		command => $TTPVars->{config}{toops}{moveDir}{byOS}{$Config{osname}}{command},
		macros => {
			SOURCE => $source,
			TARGET => $target
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
	} else {
		$result = copyDir( $source, $target ) && removeTree( $source );
	}
	msgVerbose( "Toops::moveDir() result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# dummy message
sub msgDummy {
	if( $TTPVars->{run}{dummy} ){
		Mods::MessageLevel::print({
			msg => shift,
			level => DUMMY,
			withColor => $TTPVars->{run}{colored}
		});
	}
	return true;
}

# -------------------------------------------------------------------------------------------------
# Error message - always logged
sub msgErr {
	# let have a stack trace
	stackTrace() if $TTPVars->{Toops}{stackOnErr};
	# and send the message
	Mods::MessageLevel::print({
		msg => shift,
		level => ERR,
		handle => \*STDERR,
		withColor => $TTPVars->{run}{colored}
	});
	$TTPVars->{run}{exitCode} += 1;
}

# -------------------------------------------------------------------------------------------------
# prefix and log a message
sub msgLog {
	my $msg = shift;
	my $ref = ref( $msg );
	if( $ref eq 'ARRAY' ){
		foreach my $line ( split( /[\r\n]/, @{$msg} )){
			chomp $line;
			msgLog( $line );
		}
	} elsif( !$ref ){
		msgLogAppend( Mods::Toops::msgPrefix().$msg );
	} else {
		msgLog( "unmanaged type '$ref' for '$msg'" );
	}
}

# -------------------------------------------------------------------------------------------------
# log an already prefixed message
# do not try to write in logs while they are not initialized
# the host config is silently reevaluated on each call to be sure we are writing in the logs of the day

sub msgLogAppend {
	my ( $msg ) = @_;
	if( $TTPVars->{run}{logsMain} ){
		my $host = uc hostname;
		my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
		my $line = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%5N' )." $host $username $msg";
		path( $TTPVars->{run}{logsMain} )->append_utf8( $line.EOL );
	}
}

# -------------------------------------------------------------------------------------------------
# Also logs msgOut or msgVerbose (or others) messages depending of:
# - whether the passed-in options have a truethy 'withLog'
# - whether the corresponding option is set in Toops site configuration
# - defaulting to truethy (Toops default is to log everything)
sub msgLogIf {
	# the ligne which has been {config}{ed
	my $msg = shift;
	# the caller options - we search here for a 'withLog' option
	my $opts = shift || {};
	# the key in site configuration
	my $key = shift || '';
	# where default is true
	my $withLog = true;
	$withLog = $TTPVars->{config}{toops}{$key} if $key and exists $TTPVars->{config}{toops}{$key};
	$withLog = $opts->{withLog} if exists $opts->{withLog};
	Mods::Toops::msgLogAppend( $msg ) if $withLog;
}

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (E):
# - the message to be {config}{ed
# - (optional) a hash options with 'withLog=true|false'
#   which override the site configuration , with itself overrides the Toops default which is true
sub msgOut {
	my $msg = shift;
	my $opts = shift || {};
	my $line = Mods::Toops::msgPrefix().$msg;
	print $line.EOL;
	Mods::Toops::msgLogIf( $line, $opts, 'msgOut' );
}

# -------------------------------------------------------------------------------------------------
# Compute the message prefix, including a trailing space
sub msgPrefix {
	my $prefix = '';
	if( $TTPVars->{run}{command}{basename} ){
		$prefix = "[$TTPVars->{run}{command}{basename}";
		$prefix .= ' '.$TTPVars->{run}{verb}{name} if $TTPVars->{run}{verb}{name};
		$prefix.= '] ';
	} elsif( $TTPVars->{run}{daemon}{name} ){
		$prefix = "[$TTPVars->{run}{daemon}{name}";
		$prefix .= ' '.$TTPVars->{run}{daemon}{add} if $TTPVars->{run}{daemon}{add};
		$prefix.= '] ';
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (E):
# - the message to be {config}{ed
# - (optional) a hash options with following options:
#   > verbose=true|false
#     overrides the --verbose option of the running command/verb
#   > withLog=true|false
#     overrides the site configuration , with itself overrides the Toops default which is true
sub msgVerbose {
	my $msg = shift;
	my $opts = shift || {};
	#my $line = Mods::Toops::msgPrefix()."(VERB) $msg";
	# be verbose to console ?
	my $verbose = false;
	$verbose = $TTPVars->{run}{verbose} if exists( $TTPVars->{run}{verbose} );
	$verbose = $opts->{verbose} if exists( $opts->{verbose} );
	# be verbose in log ?
	my $withLog = true;
	$withLog = $TTPVars->{config}{toops}{msgVerbose}{withLog} if exists $TTPVars->{config}{toops}{msgVerbose}{withLog};
	$withLog = $opts->{withLog} if exists $opts->{withLog};
	Mods::MessageLevel::print({
		msg => $msg,
		level => VERBOSE,
		withConsole => $verbose,
		withColor => $TTPVars->{run}{colored},
		withLog => $withLog
	});
}

# -------------------------------------------------------------------------------------------------
# Warning message - always logged
# (E):
# - the single warning message
sub msgWarn {
	Mods::MessageLevel::print({
		msg => shift,
		level => WARN
	});
}

# -------------------------------------------------------------------------------------------------
# pad the provided string until the specified length with the provided char
sub pad {
	my( $str, $length, $pad ) = @_;
	while( length( $str ) < $length ){
		$str .= $pad;
	}
	return $str;
}

# -------------------------------------------------------------------------------------------------
# returns the path requested by the given command
# (E):
# - the command to be executed
# - an optional options hash with following keys:
#   > mustExists, defaulting to false
sub pathFromCommand {
	my( $cmd, $opts ) = @_;
	$opts //= {};
	msgErr( "Toops::pathFromCmd() command is not specified" ) if !$cmd;
	my $path = undef;
	if( !errs()){
		$path = `$cmd`;
		msgErr( "Toops::pathFromCmd() command doesn't output anything" ) if !$path;
	}
	if( !errs()){
		my @words = split( /\s+/, $path );
		$path = $words[scalar @words - 1];
	}
	my $mustExists = false;
	$mustExists = $opts->{mustExists} if exists $opts->{mustExists};
	if( $mustExists && !-r $path ){
		msgErr( "Toops::pathFromCmd() path='$path' doesn't exist or is not readable" );
		$path = undef;
	}
	return $path;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing character
sub pathRemoveTrailingChar {
	my $line = shift;
	my $char = shift;
	if( substr( $line, -1 ) eq $char ){
		$line = substr( $line, 0, length( $line )-1 );
	}
	return $line;
}

# -------------------------------------------------------------------------------------------------
# Remove the trailing path separator
sub pathRemoveTrailingSeparator {
	my $dir = shift;
	my $sep = File::Spec->catdir( '' );
	return Mods::Toops::pathRemoveTrailingChar( $dir, $sep );
}

# -------------------------------------------------------------------------------------------------
# Make sure we returns a path with a traiing separator
sub pathWithTrailingSeparator {
	my $dir = shift;
	$dir = Mods::Toops::pathRemoveTrailingSeparator( $dir );
	my $sep = File::Spec->catdir( '' );
	$dir .= $sep;
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# delete a directory and all its content
sub removeTree {
	my ( $dir ) = @_;
	my $result = true;
	msgVerbose( "Toops::removeTree() removing '$dir'" );
	my $error;
	remove_tree( $dir, {
		verbose => $TTPVars->{run}{verbose},
		error => \$error
	});
	# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
	if( $error && @$error ){
		for my $diag ( @$error ){
			my ( $file, $message ) = %$diag;
			if( $file eq '' ){
				msgErr( "remove_tree() $message" );
			} else {
				msgErr( "remove_tree() $file: $message" );
			}
		}
		$result = false;
	}
	msgVerbose( "Toops::removeTree() dir='$dir' result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments
sub run {
	init();
	$TTPVars->{run}{command}{path} = $0;
	$TTPVars->{run}{command}{started} = Time::Moment->now;
	my @command_args = @ARGV;
	$TTPVars->{run}{command}{args} = \@ARGV;
	my ( $volume, $directories, $file ) = File::Spec->splitpath( $TTPVars->{run}{command}{path} );
	my $command = $file;
	$TTPVars->{run}{command}{basename} = $command;
	$TTPVars->{run}{command}{directory} = Mods::Toops::pathRemoveTrailingSeparator( $directories );
	$command =~ s/\.[^.]+$//;
	# make sure the command is not a reserved word
	if( grep( /^$command$/, @{$TTPVars->{Toops}{ReservedWords}} )){
		Mods::Toops::msgErr( "command '$command' is a Toops reserved word. Aborting." );
		Mods::Toops::ttpExit();
	}
	$TTPVars->{run}{command}{name} = $command;
	# the directory where are stored the verbs of the command
	my @dirs = File::Spec->splitdir( $TTPVars->{run}{command}{directory} );
	pop( @dirs );
	$TTPVars->{run}{command}{verbsDir} = File::Spec->catdir( $volume, @dirs, $command );
	# prepare for the datas of the command
	$TTPVars->{$command} = {};
	# first argument is supposed to be the verb
	if( scalar @command_args ){
		$TTPVars->{run}{verb}{name} = shift( @command_args );
		$TTPVars->{run}{verb}{args} = \@command_args;
		# as verbs are written as Perl scripts, they are dynamically ran from here
		local @ARGV = @command_args;
		$TTPVars->{run}{help} = scalar @ARGV ? false : true;
		$TTPVars->{run}{verb}{path} = File::Spec->catdir( $TTPVars->{run}{command}{verbsDir}, $TTPVars->{run}{verb}{name}.$TTPVars->{Toops}{verbSufix} );
		if( -f $TTPVars->{run}{verb}{path} ){
			unless( defined do $TTPVars->{run}{verb}{path} ){
				msgErr( "do $TTPVars->{run}{verb}{path}: ".( $! || $@ ));
			}
		} else {
			Mods::Toops::msgErr( "script not found or not readable: '$TTPVars->{run}{verb}{path}' (most probably, '$TTPVars->{run}{verb}{name}' is not a valid verb)" );
		}
	} else {
		Mods::Toops::helpCommand();
		ttpExit();
	}
}

# -------------------------------------------------------------------------------------------------
# Recursively search the provided array to find all occurrences of provided key
# (E):
# - array to be searched for
# - searched key
# - an optional options hash, which may have following keys:
#   > none at the moment
# (S):
# returns a hash whose keys are the found workload names, values being arrays of key paths
sub searchRecArray {
	my ( $array, $searched, $opts, $recData ) = @_;
	$opts //= {};
	$recData //= {};
	$recData->{path} = [] if !exists $recData->{path};
	$recData->{result} = {} if !exists $recData->{path};
	foreach my $it ( @{$array} ){
		my $type = ref( $it );
		if( $type eq 'ARRAY' ){
			push( @{$recData->{path}}, '' );
			Mods::Toops::searchRecArray( $it, $searched, $opts, $recData );
		} elsif( $type eq 'HASH' ){
			push( @{$recData->{path}}, '' );
			Mods::Toops::searchRecHash( $it, $searched, $opts, $recData );
		}
	}
	return $recData;
}

# -------------------------------------------------------------------------------------------------
# Recursively search the provided hash to find all occurrences of provided key
# (E):
# - hash to be searched for
# - searched key
# - an optional options hash, which may have following keys:
#   > none at the moment
# (S):
# returns a hash whose keys are the found names, values being arrays of key paths
sub searchRecHash {
	my ( $hash, $searched, $opts, $recData ) = @_;
	$opts //= {};
	$recData //= {};
	$recData->{path} = [] if !exists $recData->{path};
	$recData->{result} = [] if !exists $recData->{path};
	foreach my $key ( keys %{$hash} ){
		if( $key eq $searched ){
			push( @{$recData->{result}}, { path => $recData->{path}, data => $hash->{$key} });
		} else {
			my $ref = $hash->{$key};
			my $type = ref( $ref );
			if( $type eq 'ARRAY' ){
				push( @{$recData->{path}}, $key );
				Mods::Toops::searchRecArray( $ref, $searched, $opts, $recData );
			} elsif( $type eq 'HASH' ){
				push( @{$recData->{path}}, $key );
				Mods::Toops::searchRecHash( $ref, $searched, $opts, $recData );
			}
		}
	}
	return $recData;
}

# -------------------------------------------------------------------------------------------------
# print a stack trace
# https://stackoverflow.com/questions/229009/how-can-i-get-a-call-stack-listing-in-perl

sub stackTrace {
	my $trace = Devel::StackTrace->new;
	print $trace->as_string; # like carp
}

# -------------------------------------------------------------------------------------------------
# exit the command
# Return code is optional, defaulting to TTPVars->{run}{exitCode}
sub ttpExit {
	my $rc = shift || $TTPVars->{run}{exitCode};
	if( $rc ){
		msgErr( "exiting with code $rc" );
	} else {
		msgVerbose( "exiting with code $rc" );
	}
	exit $rc;
}

# -------------------------------------------------------------------------------------------------
# re-evaluate both toops and host configurations
# Rationale: we could have decided to systematically reevaluate the configuration data at each use
# with the benefit that the data is always up to date
# with the possible inconvenient of a rare condition where a command+verb execution will be logged
# in two different log files, for example if executed between 23:59:59 and 00:00:01 and logs are daily.
# So this a design decision to only evaluate the logs once at initialization of the standard 
# command+verb execution.
# The daemons which make use of TheToolsProject have their own decisions to be taken, but habits
# want that daemons writes in the current log, not in an old one..
sub ttpEvaluate {
	# first initialize the targets so that the evaluations have values to replace with
	foreach my $key ( @{$TTPVars->{Toops}{ConfigKeys}} ){
		$TTPVars->{config}{$key} = $TTPVars->{Toops}{json}{$key};
	}
	# then evaluate
	# sort the keys to try to get something which is predictable
	foreach my $key ( sort @{$TTPVars->{Toops}{ConfigKeys}} ){
		$TTPVars->{config}{$key} = evaluate( $TTPVars->{config}{$key} );
	}
	# and reevaluates the logs too
	$TTPVars->{run}{logsDir} = Mods::Path::logsDailyDir();
	$TTPVars->{run}{logsMain} = File::Spec->catdir( $TTPVars->{run}{logsDir}, 'main.log' );
}

# -------------------------------------------------------------------------------------------------
# given a command output, extracts the [command.pl verb] lines, returning the rest
sub ttpFilter {
	my @lines = @_;
	my @result = ();
	foreach my $it ( @lines ){
		chomp $it;
		$it =~ s/^\s*//;
		$it =~ s/\s*$//;
		push( @result, $it ) if ! grep( /\[[^\]]+\]/, $it );
	}
	return \@result;
}

# -------------------------------------------------------------------------------------------------
# Used by verbs to access our global variables
sub TTPVars {
	return $TTPVars;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from toops.json, maybe overriden in host configuration
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host)
# (O):
# - the evaluated value of this variable, which may be undef
#   must be a scaler
sub var {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	my $result = varSearch( $keys, $TTPVars->{config}{toops} );
	my $config = $TTPVars->{config}{host};
	$config = $opts->{config} if exists $opts->{config};
	my $hostValue = varSearch( $keys, $config );
	$result = $hostValue if defined $hostValue;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the provided base
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
# (O):
# - the evaluated value of this variable, which may be undef
#   must be a scaler
sub varSearch {
	my ( $keys, $base ) = @_;
	my $result = undef;
	my $found = true;
	for my $k ( @{$keys} ){
		if( exists( $base->{$k} )){
			$base = $base->{$k};
		} else {
			$found = false;
			last;
		}
	}
	if( $found && !ref( $base )){
		$result = $base;
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# whether we are running in dummy mode
sub wantsDummy {
	return $TTPVars->{run}{dummy};
}

# -------------------------------------------------------------------------------------------------
# whether help has been required
sub wantsHelp {
	return $TTPVars->{run}{help};
}

1;
