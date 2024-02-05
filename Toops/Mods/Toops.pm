# Copyright (@) 2023-2024 PWI Consulting

package Mods::Toops;

use strict;
use warnings;

use Config;
use Data::Dumper;
use File::Copy qw( copy move );
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
		# some internally used constants
		commentPreUsage => '^# @\(#\) ',
		commentPostUsage => '^# @\(@\) ',
		commentUsage => '^# @\(-\) ',
		verbSufix => '.do.pl',
		verbSed => '\.do\.pl'
	},
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
	my $prev = undef;
	my $result = _evaluateRec( $value );
	while( !eq_deeply( $result, $prev )){
		$prev = $result;
		$result = _evaluateRec( $prev );
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
	msgErr( "scalar expected, but '$type' found" ) if $type;
	my $result = $value || '';
	# this weird code to let us manage some level of pseudo recursivity
	$result =~ s/\[eval:([^\]]+)\]/_evaluatePrint( $1 )/eg;
	$result =~ s/\[_eval:/[eval:/g;
	$result =~ s/\[__eval:/[_eval:/g;
	$result =~ s/\[___eval:/[__eval:/g;
	$result =~ s/\[____eval:/[___eval:/g;
	$result =~ s/\[_____eval:/[____eval:/g;
	return $result;
}

sub _evaluatePrint {
	my ( $value ) = @_;
	my $result = eval $value;
	#print "value='$value' result='$result'".EOL;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# append a record to our daily executions report
# (E):
# - the data provided to be recorded
# This function automatically appends:
# - hostname
# - start timestamp
# - end timestamp
# - return code
# - full run command
sub execReportAppend {
	my ( $data ) = @_;
	# add some auto elements
	$data->{cmdline} = "$0 ".join( ' ', @{$TTPVars->{run}{command}{args}} );
	$data->{command} = $TTPVars->{run}{command}{basename};
	$data->{verb} = $TTPVars->{run}{verb}{name};
	$data->{host} = uc hostname;
	$data->{code} = $TTPVars->{run}{exitCode};
	$data->{started} = $TTPVars->{run}{command}{started}->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	# and build the target full path
	my $path = File::Spec->catdir( $TTPVars->{config}{site}{toops}{execReports}, Time::Moment->now->strftime( '%Y%m%d%H%M%S%6N.json' ));
	jsonWrite( $data, $path );
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
# returns the host config
sub getHostConfig {
	my $host = uc hostname;
	return $TTPVars->{config}{$host};
}

# -------------------------------------------------------------------------------------------------
# returns the list of JSON configuration full pathnames for defined hosts (including this one)
sub getJsonHosts {
	my $dir = File::Spec->catdir( $ENV{TTP_SITE}, "machines" );
	my @hosts = glob( $dir."/*.json" );
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
sub helpVerb {
	my ( $defaults ) = @_;
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
	@verbHelp = Mods::Toops::grepFileByRegex( $TTPVars->{run}{verb}{path}, $TTPVars->{Toops}{commentUsage}, { warnIfSeveral => false });
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
# get the machine services configuration as a hash indexed by hostname
#  HostConf::init() is expected to return a hash with a single top key which is the hostname
#  we check and force that here
#  + set the host as a value to be more easily available
sub initHostConfiguration {
	my $host = uc hostname;
	my $conf = File::Spec->catdir( $ENV{TTP_SITE}, "machines", $host.'.json' );
	my $hash = jsonRead( $conf );
	my $hash_host = uc (( keys %{$hash} )[0] );
	msgErr( "hostname '$host' expected, found '$hash_host'" ) if $hash_host ne $host;
	if( !errs()){
		# rationale: evaluate() may want take advantage of the TTPVars content, so must be set before evaluation
		$TTPVars->{config}{$host} = $hash->{$host};
		$TTPVars->{config}{$host} = evaluate( $TTPVars->{config}{$host} );
		$TTPVars->{config}{$host}{name} = $host;
	}
}

# -------------------------------------------------------------------------------------------------
# Initialize the logs
# Expects the site configuration has a 'toops/logsDir' variable, defaulting to /tmp/Toops/logs in unix and C:\Temps\Toops\logs in Windows
# Make sure the daily directory exists
sub initLogs {
	my $logsDir = File::Spec->catdir( $TTPVars->{Toops}{defaults}{$Config{osname}}{tempDir}, 'Toops', 'logs' );
	$logsDir = $TTPVars->{config}{site}{toops}{logsDir} if exists $TTPVars->{config}{site}{toops}{logsDir};
	make_path( $logsDir );
	$TTPVars->{run}{logsMain} = File::Spec->catdir( $logsDir, 'main.log' );
}

# -------------------------------------------------------------------------------------------------
# Make sure we have a site configuration JSON file and loads and interprets it
sub initSiteConfiguration {
	my $conf = File::Spec->catdir( $ENV{TTP_SITE}, 'toops.json' );
	$TTPVars->{config}{site} = jsonRead( $conf );
	# rationale: evaluate() may want take advantage of the TTPVars content, so must be set before evaluation
	$TTPVars->{config}{site} = evaluate( $TTPVars->{config}{site} );
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
	makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	path( $path )->append_utf8( $str.EOL );
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# All Toops JSON configuration files may take advantage of dynamic eval here
# (E):
# - the full path to the to-be-loaded-and-interpreted json file
sub jsonRead {
	my ( $conf ) = @_;
	my $result = undef;
	if( -f $conf ){
		my $content = do {
		   open( my $fh, "<:encoding(UTF-8)", $conf ) or msgErr( "Can't open '$conf': $!".EOL );
		   local $/;
		   <$fh>
		};
		my $json = JSON->new;
		$result = $json->decode( $content );
	} else {
		Mods::Toops::msgWarn( "site configuration file '$conf' not found or not readable" );
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
	msgVerbose( "jsonWrite().. to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	path( $path )->spew_utf8( $str.EOL );
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
sub makeDirExist {
	my ( $dir ) = @_;
	my $result = false;
	if( -d $dir ){
		msgVerbose( "Toops::makeDirExist() dir='$dir' already exists" );
		$result = true;
	# seems that make_path is not easy with UNC path (actually seems that make_path just dies)
	} elsif( $dir =~ /^\\\\/ ){
		msgVerbose( "Toops::makeDirExist() dir='$dir' is a UNC path, recursing by level" );
		my @levels = ();
		my $candidate = $dir;
		my ( $volume, $directories, $file ) = File::Spec->splitpath( $candidate );
		my $other;
		unshift( @levels, $file );
		while( length $directories > 1 ){
			$candidate = Mods::Toops::pathRemoveTrailingSeparator( $directories );
			( $other, $directories, $file ) = File::Spec->splitpath( $candidate );
			unshift( @levels, $file );
		}
		$candidate = '';
		$result = true;
		while( scalar @levels ){
			my $level = shift @levels;
			my $dir = File::Spec->catpath( $volume, $candidate, $level );
			$result &= msgDummy( "mkdir $dir" );
			if( !wantsDummy()){
				$result &= mkdir $dir;
			}
			$candidate = File::Spec->catdir(  $candidate, $level );
		}
	} else {
		msgVerbose( "Toops::makeDirExist() dir='$dir' tries make_path()" );
		$result &= msgDummy( "make_path( $dir )" );
		if( !wantsDummy()){
			my $error;
			make_path( $dir, {
				verbose => $TTPVars->{run}{verbose},
				error => \$error
			});
			# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
			if( $error && @$error ){
				for my $diag ( @$error ){
					my ( $file, $message ) = %$diag;
					if( $file eq '' ){
						msgErr( $message );
					} else {
						msgErr( "$file: $message" );
					}
				}
				$result = false;
			}
		}
	}
	msgVerbose( "Toops::makeDirExist() dir='$dir' result=$result" );
	return $result;
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
		$result = true;
	} else {
		my $command = undef;
		$command = $TTPVars->{config}{site}{toops}{moveDir}{$Config{osname}}{command} if exists $TTPVars->{config}{site}{toops}{moveDir}{$Config{osname}}{command};
		if( $command ){
			msgVerbose( "found command='$command'" );
			$result = eval $command;
		} else {
			$result = moveDirFC( $source, $target );
		}
	}
	msgVerbose( "Toops::moveDir() result=$result" );
	return $result;
}

# -------------------------------------------------------------------------------------------------
# standard File::Copy version - only suitable with standard (not too big with reasonably available target space) files
sub moveDirFC {
	my ( $source, $target ) = @_;
	my $result = false;
	msgVerbose( "Toops::moveDir() source='$source' target='$target'" );
	opendir( FD, "$source" ) || msgErr( "unable to open directory $source: $!" );
	$result = makeDirExist( $target ) if !errs();
	if( $result ){
		while( my $it = readdir( FD )){
			next if $it eq "." or $it eq "..";
			my $srcpath = File::Spec->catdir( $source, $it );
			my $dstpath = File::Spec->catdir( $target, $it );
			if( -d $srcpath ){
				$result &= moveDir( $srcpath, $dstpath );
				next;
			}
			msgVerbose( "Toops::moveDir() moving '$srcpath' to '$dstpath'" );
			msgDummy( "move( $srcpath, $dstpath )" );
			if( !wantsDummy()){
				$result = move( $srcpath, $dstpath );
				msgVerbose( "Toops::moveDir() result=$result" );
			}
			last if !$result;
		}
	}
	closedir( FD );
	if( !errs() && $result ){
		$result = removeTree( $source );
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
	Mods::Toops::msgLogAppend( Mods::Toops::msgPrefix().$msg );
}

# -------------------------------------------------------------------------------------------------
# log an already prefixed message
# do not try to write in logs while they are not initialized
sub msgLogAppend {
	my $msg = shift;
	if( $TTPVars->{run}{logsMain} ){
		my $host = uc hostname;
		my $username = $ENV{LOGNAME} || $ENV{USER} || $ENV{USERNAME} || 'unknown'; #getpwuid( $< );
		my $line = localtime->strftime( '%Y-%m-%d %H:%M:%S' )." $host $username $msg";
		path( $TTPVars->{run}{logsMain} )->append_utf8( $line.EOL );
	}
}

# -------------------------------------------------------------------------------------------------
# Also logs msgOut or msgVerbose (or others) messages depending of:
# - whether the passed-in options have a truethy 'withLog'
# - whether the corresponding option is set in Toops site configuration
# - defaulting to truethy (Toops default is to log everything)
sub msgLogIf {
	# the ligne which has been printed
	my $msg = shift;
	# the caller options - we search here for a 'withLog' option
	my $opts = shift || {};
	# the key in site configuration
	my $key = shift || '';
	# where default is true
	my $withLog = true;
	$withLog = $TTPVars->{config}{site}{toops}{$key} if $key and exists $TTPVars->{config}{site}{toops}{$key};
	$withLog = $opts->{withLog} if exists $opts->{withLog};
	Mods::Toops::msgLogAppend( $msg ) if $withLog;
}

# -------------------------------------------------------------------------------------------------
# standard message on stdout
# (E):
# - the message to be printed
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
		$prefix = "[$TTPVars->{run}{daemon}{name}] ";
	}
	return $prefix;
}

# -------------------------------------------------------------------------------------------------
# Verbose message
# (E):
# - the message to be printed
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
	$withLog = $TTPVars->{config}{site}{toops}{msgVerbose}{withLog} if exists $TTPVars->{config}{site}{toops}{msgVerbose}{withLog};
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
	my $result = false;
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
				msgErr( $message );
			} else {
				msgErr( "$file: $message" );
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
	Mods::Toops::initSiteConfiguration();
	Mods::Toops::initLogs();
	Mods::Toops::msgLog( "executing $0 ".join( ' ', @ARGV ));
	Mods::Toops::initHostConfiguration();
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
# exit the command
# Return code is optional, defaulting to exitCode
sub ttpExit {
	my $rc = shift || $TTPVars->{run}{exitCode};
	if( $rc ){
		msgOut( "exiting with code $rc" );
	} else {
		Mods::Toops::msgVerbose( "exiting with code $rc" );
	}
	exit $rc;
}

# -------------------------------------------------------------------------------------------------
# Used by verbs to access our global variables
sub TTPVars {
	return $TTPVars;
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
