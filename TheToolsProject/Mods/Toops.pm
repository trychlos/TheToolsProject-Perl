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
use Try::Tiny;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Telemetry;
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
# (I):
# argument is a hash with following keys:
# - command: the command to be evaluated and executed, may be undef
# - macros: a hash of the macros to be replaced where:
#   > key is the macro name, must be labeled in the toops.json as '<macro>' (i.e. between angle brackets)
#   > value is the value to be replaced
# (O):
# return a hash with following keys:
# - evaluated: the evaluated command after macros replacements
# - return: original exit code of the command
# - result: true|false
sub commandByOs {
	my ( $args ) = @_;
	my $result = {};
	$result->{command} = $args->{command};
	$result->{result} = false;
	Mods::Message::msgVerbose( "Toops::commandByOs() evaluating and executing command='".( $args->{command} || '(undef)' )."'" );
	if( defined $args->{command} ){
		$result->{evaluated} = $args->{command};
		foreach my $key ( keys %{$args->{macros}} ){
			$result->{evaluated} =~ s/<$key>/$args->{macros}{$key}/;
		}
		Mods::Message::msgVerbose( "Toops::commandByOs() evaluated to '$result->{evaluated}'" );
		Mods::Message::msgDummy( $result->{evaluated} );
		if( !wantsDummy()){
			my $out = `$result->{evaluated}`;
			print $out;
			Mods::Message::msgLog( $out );
			# https://www.perlmonks.org/?node_id=81640
			# Thus, the exit value of the subprocess is actually ($? >> 8), and $? & 127 gives which signal, if any, the
			# process died from, and $? & 128 reports whether there was a core dump.
			# https://ss64.com/nt/robocopy-exit.html
			my $res = $?;
			$result->{result} = ( $res == 0 ) ? true : false;
			Mods::Message::msgVerbose( "Toops::commandByOs() return_code=$res firstly interpreted as result=$result->{result}" );
			if( $args->{command} =~ /robocopy/i ){
				$res = ( $res >> 8 );
				$result->{result} = ( $res <= 7 ) ? true : false;
				Mods::Message::msgVerbose( "Toops::commandByOs() robocopy specific interpretation res=$res result=$result->{result}" );
			}
		} else {
			$result->{result} = true;
		}
	}
	Mods::Message::msgVerbose( "Toops::commandByOs() result=$result->{result}" );
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
	Mods::Message::msgVerbose( "Toops::copyDir() entering with source='$source' target='$target'" );
	if( ! -d $source ){
		Mods::Message::msgErr( "$source: source directory doesn't exist" );
		return false;
	}
	my $cmdres = commandByOs({
		command => var([ 'copyDir', 'byOS', $Config{osname}, 'command' ]),
		macros => {
			SOURCE => $source,
			TARGET => $target
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		Mods::Message::msgVerbose( "Toops::copyDir() commandByOs() result=$result" );
	} else {
		Mods::Message::msgDummy( "dircopy( $source, $target )" );
		if( !wantsDummy()){
			# https://metacpan.org/pod/File::Copy::Recursive
			# This function returns true or false: for true in scalar context it returns the number of files and directories copied,
			# whereas in list context it returns the number of files and directories, number of directories only, depth level traversed.
			my $res = dircopy( $source, $target );
			$result = $res ? true : false;
			Mods::Message::msgVerbose( "Toops::copyDir() dircopy() res=$res result=$result" );
		}
	}
	Mods::Message::msgVerbose( "Toops::copyDir() returns result=$result" );
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
	Mods::Message::msgVerbose( "Toops::copyFile() entering with source='$source' target='$target'" );
	# isolate the file from the source directory path
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $source );
	my $srcpath = File::Spec->catpath( $vol, $dirs );
	my $cmdres = commandByOs({
		command => var([ 'copyFile', 'byOS', $Config{osname}, 'command' ]),
		macros => {
			SOURCE => $srcpath,
			TARGET => $target,
			FILE => $file
		}
	});
	if( defined $cmdres->{command} ){
		$result = $cmdres->{result};
		Mods::Message::msgVerbose( "Toops::copyFile() commandByOs() result=$result" );
	} else {
		Mods::Message::msgDummy( "copy( $source, $target )" );
		if( !wantsDummy()){
			# https://metacpan.org/pod/File::Copy
			# This function returns true or false
			$result = copy( $source, $target );
			if( $result ){
				Mods::Message::msgVerbose( "Toops::copyFile() result=true" );
			} else {
				Mods::Message::msgErr( "Toops::copyFile() $!" );
			}
		}
	}
	Mods::Message::msgVerbose( "Toops::copyFile() returns result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# is there any error ?
#  exit code may be seen as an error counter as it is incremented by Message::msgErr()
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
		Mods::Message::msgErr( "scalar expected, but '$type' found" );
		$evaluate = false;
	}
	my $result = $value || '';
	if( $evaluate ){
		my $re = qr/
			[^\[]*	# anything which doesn't contain any '['
			|
			[^\[]* \[(?>[^\[\]]|(?R))*\] [^\[]*
		/x;
		
		if( false ){
			my @matches = $result =~ /\[eval:($re)\]/g;
			print "line='$result'".EOL;
			print Dumper( @matches );
		}
		
		# this weird code to let us manage some level of pseudo recursivity
		$result =~ s/\[eval:($re)\]/_evaluatePrint( $1 )/eg;
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
# report an execution
# The exact data, the target to report to and the used medium are up to the caller.
# But at the moment we manage a) a JSON execution report file and b) a MQTT message.
# This is a design decision to limit TTP to these medias because:
# - we do not want have here some code for each and every possible medium a caller may want use a day or another
# - as soon as we can have either a JSON file or a MQTT message, or even both of these medias, we can also have
#   any redirection from these medias to another one (e.g. scan the execution report JSON files and do something
#   when a new one is detected, or listen to the MQTT bus and suibscribe to interesting topics, and so on...).
# Each medium is only evaluated if and only if:
# - the corresponding 'enabled' option is 'true' for the considered host
# - and the relevant options are provided by the caller. 
# (I):
# - A ref to a hash with following keys:
#   > file: a ref to a hash with following keys:
#     - data: a ref to a hash to be written as JSON execution report data
#   > mqtt: a ref to a hash with following keys:
#     - data: a ref to a hash to be written as MQTT payload (in JSON format)
#     - topic as a mandatory string
#     - options, as an optional string
# This function automatically appends:
# - hostname
# - start timestamp
# - end timestamp
# - return code
# - full run command
sub executionReport {
	my ( $args ) = @_;
	# write JSON file if configuration enables that and relevant arguments are provided
	my $enabled = var([ 'executionReports', 'withFile', 'enabled' ]);
	if( $enabled && $args->{file} ){
		_executionReportToFile( $args->{file} );
	}
	# publish MQTT message if configuration enables that and relevant arguments are provided
	$enabled = var([ 'executionReports', 'withMqtt', 'enabled' ]);
	if( $enabled && $args->{mqtt} ){
		_executionReportToMqtt( $args->{mqtt} );
	}
}

# -------------------------------------------------------------------------------------------------
# Complete the provided data with the data colected by TTP
sub _executionReportCompleteData {
	my ( $data ) = @_;
	$data->{cmdline} = "$0 ".join( ' ', @{$TTPVars->{run}{command}{args}} );
	$data->{command} = $TTPVars->{run}{command}{basename};
	$data->{verb} = $TTPVars->{run}{verb}{name};
	$data->{host} = uc hostname;
	$data->{code} = $TTPVars->{run}{exitCode};
	$data->{started} = $TTPVars->{run}{command}{started}->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{dummy} = $TTPVars->{run}{dummy};
	return $data;
}

# -------------------------------------------------------------------------------------------------
# write an execution report to a file
# the needed command is expected to be configured
# (I):
# - a hash ref with following keys:
#   > data, a hash ref
# (O):
# - returns true|false
sub _executionReportToFile {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if exists $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $command = var([ 'executionReports', 'withFile', 'command' ]);
		if( $command ){
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $colored = $TTPVars->{run}{colored} ? "-colored" : "-nocolored";
			my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
			my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
			print `$command $colored $dummy $verbose`;
			#$? = 256
			$res = $? == 0;
		} else {
			Mods::Message::msgErr( "executionReportToFile() expected a 'command' argument, not found" );
		}
	} else {
		Mods::Message::msgErr( "executionReportToFile() expected a 'data' argument, not found" );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# send an execution report on the MQTT bus if Toops is configured for
# (I):
# - a hash ref with following keys:
#   > data, a hash ref
#   > topic, as a string
#   > options, as a string
sub _executionReportToMqtt {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if exists $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $topic = undef;
		$topic = $args->{topic} if exists $args->{topic};
		if( $topic ){
			my $command = var([ 'executionReports', 'withMqtt', 'command' ]);
			if( $command ){
				my $json = JSON->new;
				my $str = $json->encode( $data );
				$command =~ s/<TOPIC>/$topic/;
				$command =~ s/<PAYLOAD>/$str/;
				my $options = $args->{options} ? $args->{options} : "";
				$command =~ s/<OPTIONS>/$options/;
				my $colored = $TTPVars->{run}{colored} ? "-colored" : "-nocolored";
				my $dummy = $TTPVars->{run}{dummy} ? "-dummy" : "-nodummy";
				my $verbose = $TTPVars->{run}{verbose} ? "-verbose" : "-noverbose";
				print `$command $colored $dummy $verbose`;
				$res = $? == 0;
			} else {
				Mods::Message::msgErr( "executionReportToMqtt() expected a 'command' argument, not found" );
			}
		} else {
			Mods::Message::msgErr( "executionReportToMqtt() expected a 'topic' argument, not found" );
		}
	} else {
		Mods::Message::msgErr( "executionReportToMqtt() expected a 'data' argument, not found" );
	}
	return $res;
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
	my $tempfname = File::Spec->catdir( Mods::Path::logsDailyDir(), "$fname-$random.tmp" );
	Mods::Message::msgVerbose( "getTempFileName() tempfname='$tempfname'" );
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
		Mods::Message::msgWarn( "'$filename' doesn't have any line with the searched content ('$regex')." ) if $warnIfNone;
	} else {
		# warn if there are several lines in the grepped result ?
		my $warnIfSeveral = true;
		$warnIfSeveral = $opts->{warnIfSeveral} if exists $opts->{warnIfSeveral};
		if( scalar @grepped > 1 ){
			Mods::Message::msgWarn( "'$filename' has more than one line with the searched content ('$regex')." ) if $warnIfSeveral;
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
	Mods::Message::msgVerbose( "helpCommand()" );
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
	Mods::Message::msgVerbose( "helpVerb()" );
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
		Mods::Message::msgErr( "hostConfigRead() hostname expected" );
	} else {
		my $hash = jsonRead( Mods::Path::hostConfigurationPath( $host ));
		if( $hash ){
			my $topkey = ( keys %{$hash} )[0];
			if( $topkey ne $host ){
				Mods::Message::msgErr( "expected toplevel key '$host', found '$topkey'" ) ;
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
	Mods::Message::msgLog( "executing $0 ".join( ' ', @ARGV ));
}

# -------------------------------------------------------------------------------------------------
# Append a JSON element to a file
# (I):
# - the hash to be written into
# - the full path to be created
# (O):
# - returns true|false
sub jsonAppend {
	my ( $hash, $path ) = @_;
	Mods::Message::msgVerbose( "jsonAppend() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	Mods::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	my $res = path( $path )->append_utf8( $str.EOL );
	Mods::Message::msgVerbose( "jsonAppend() returns ".Dumper( $res ));
	return $res ? true : false;
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file data
# (I):
# - the full path to the to-be-loaded-and-interpreted json file
sub jsonRead {
	my ( $conf ) = @_;
	Mods::Message::msgVerbose( "jsonRead() conf='$conf'" );
	my $result = undef;
	if( $conf && -r $conf ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $conf ) or Mods::Message::msgErr( "jsonRead() $conf: $!" );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		$result = $json->decode( $content );
	} elsif( $conf ){
		Mods::Message::msgErr( "jsonRead() $conf: not found or not readable" );
	} else {
		Mods::Message::msgErr( "jsonRead() expects a JSON path to be read" );
	}
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Write a hash to a JSON file
# (I):
# - the hash to be written into
# - the full path to be created
# (O):
# - returns true|false
sub jsonWrite {
	my ( $hash, $path ) = @_;
	Mods::Message::msgVerbose( "jsonWrite() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	Mods::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	# '$res' is an array with the original path and an interpreted one
	my $res = path( $path )->spew_utf8( $str.EOL );
	Mods::Message::msgVerbose( "jsonWrite() returns ".Dumper( $res ));
	return ( ref( $res ) eq 'Path::Tiny' && scalar( @{$res} ) > 0 ) ? true : false;
}

# -------------------------------------------------------------------------------------------------
# (recursively) move a directory and its content from a source to a target
# this is a design decision to make this recursive copy file by file in order to have full logs
# Toops allows to provide a system-specific command in its configuration file
# well suited for example to move big files to network storage
sub moveDir {
	my ( $source, $target ) = @_;
	my $result = false;
	Mods::Message::msgVerbose( "Toops::moveDir() source='$source' target='$target'" );
	if( ! -d $source ){
		Mods::Message::msgWarn( "$source: directory doesn't exist" );
		return true;
	}
	my $cmdres = commandByOs({
		command => var([ 'moveDir', 'byOS', $Config{osname}, 'command' ]),
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
	Mods::Message::msgVerbose( "Toops::moveDir() result=$result" );
	return $result;
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
# delete a directory and all its content
sub removeTree {
	my ( $dir ) = @_;
	my $result = true;
	Mods::Message::msgVerbose( "Toops::removeTree() removing '$dir'" );
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
				Mods::Message::msgErr( "remove_tree() $message" );
			} else {
				Mods::Message::msgErr( "remove_tree() $file: $message" );
			}
		}
		$result = false;
	}
	Mods::Message::msgVerbose( "Toops::removeTree() dir='$dir' result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Run by the command
# Expects $0 be the full path name to the command script (this is the case in Windows+Strawberry)
# and @ARGV the command-line arguments
sub run {
	init();
	try {
		$TTPVars->{run}{command}{path} = $0;
		$TTPVars->{run}{command}{started} = Time::Moment->now;
		my @command_args = @ARGV;
		$TTPVars->{run}{command}{args} = \@ARGV;
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $TTPVars->{run}{command}{path} );
		my $command = $file;
		$TTPVars->{run}{command}{basename} = $command;
		$TTPVars->{run}{command}{directory} = Mods::Path::removeTrailingSeparator( $directories );
		$command =~ s/\.[^.]+$//;
		# make sure the command is not a reserved word
		if( grep( /^$command$/, @{$TTPVars->{Toops}{ReservedWords}} )){
			Mods::Message::msgErr( "command '$command' is a Toops reserved word. Aborting." );
			ttpExit();
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
					Mods::Message::msgErr( "do $TTPVars->{run}{verb}{path}: ".( $! || $@ ));
				}
			} else {
				Mods::Message::msgErr( "script not found or not readable: '$TTPVars->{run}{verb}{path}' (most probably, '$TTPVars->{run}{verb}{name}' is not a valid verb)" );
			}
		} else {
			helpCommand();
			ttpExit();
		}
	} catch {
		Mods::Message::msgVerbose( "catching exit" );
		ttpExit();
	};
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
		Mods::Message::msgErr( "exiting with code $rc" );
	} else {
		Mods::Message::msgVerbose( "exiting with code $rc" );
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
	$TTPVars->{run}{logsMain} = File::Spec->catdir( Mods::Path::logsDailyDir(), 'main.log' );
}

# -------------------------------------------------------------------------------------------------
# given a command output, extracts the [command.pl verb] lines, returning the rest as an array
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
#   each provided key is expected to address a JSON hash object
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host), defaulting to current host config
# (O):
# - the evaluated value of this variable, which may be undef
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
sub varSearch {
	my ( $keys, $base ) = @_;
	my $found = true;
	for my $k ( @{$keys} ){
		if( exists( $base->{$k} )){
			$base = $base->{$k};
		} else {
			$found = false;
			last;
		}
	}
	return $found ? $base : undef;
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
