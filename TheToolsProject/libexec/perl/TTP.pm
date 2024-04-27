# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 1998-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2023-2024 PWI Consulting
#
# The Tools Project is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# The Tools Project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The Tools Project; see the file COPYING. If not,
# see <http://www.gnu.org/licenses/>.

package TTP;

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
use JSON;
use Path::Tiny qw( path );
use Scalar::Util qw( looks_like_number );
use Test::Deep;
use Time::Moment;
use Time::Piece;
use vars::global create => qw( $ttp );

use TTP::Constants qw( :all );
use TTP::EP;
use TTP::Message qw( :all );
use TTP::Path;

# autoflush STDOUT
$| = 1;

# store here our Toops variables
my $Const = {
	# defaults which depend of the host OS provided by 'Config' package
	byOS => {
		darwin => {
			tempDir => '/tmp'
		},
		linux => {
			tempDir => '/tmp'
		},
		MSWin32 => {
			tempDir => 'C:\\Temp'
		}
	}
};

my $TTPVars = {};

# -------------------------------------------------------------------------------------------------
# Returns the configured alertsDir (when alerts are sent by file), defaultin gto tempDir()
# (I):
# - none
# (O):
# - returns the alertsdir

sub alertsDir {
	my $dir = $ttp->var([ 'alerts', 'withFile', 'dropDir' ]) || tempDir();
	return $dir;
}

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
		command => $ttp->var([ 'copyDir', 'byOS', $Config{osname}, 'command' ]),
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
		command => $ttp->var([ 'copyFile', 'byOS', $Config{osname}, 'command' ]),
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
# Returns the current count of errors

sub errs {
	my $running = $ttp->runner();
	return $running->runnableErrs() if $running;
	return 0;
}

# -------------------------------------------------------------------------------------------------
# recursively interpret the provided data for variables and computings
#  and restart until all references have been replaced
sub evaluate {
	my ( $value ) = @_;
	my %prev = ();
	my $result = _evaluateRec( $value );
	if( $result ){
		while( !eq_deeply( $result, \%prev )){
			%prev = %{$result};
			$result = _evaluateRec( $result );
		}
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
		msgErr( "Toops::evaluateScalar() scalar expected, but '$type' found" );
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
	$result = $result || '(undef)';
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
	my $enabled = $ttp->var([ 'executionReports', 'withFile', 'enabled' ]);
	if( $enabled && $args->{file} ){
		_executionReportToFile( $args->{file} );
	}
	# publish MQTT message if configuration enables that and relevant arguments are provided
	$enabled = $ttp->var([ 'executionReports', 'withMqtt', 'enabled' ]);
	if( $enabled && $args->{mqtt} ){
		_executionReportToMqtt( $args->{mqtt} );
	}
}

# -------------------------------------------------------------------------------------------------
# Complete the provided data with the data colected by TTP
sub _executionReportCompleteData {
	my ( $data ) = @_;
	$data->{cmdline} = "$0 ".join( ' ', @{$ttp->{run}{command}{args}} );
	$data->{command} = $ttp->{run}{command}{basename};
	$data->{verb} = $ttp->{run}{verb}{name};
	$data->{host} = TTP::host();
	$data->{code} = $ttp->{run}{exitCode};
	$data->{started} = $ttp->{run}{command}{started}->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{ended} = Time::Moment->now->strftime( '%Y-%m-%d %H:%M:%S.%6N' );
	$data->{dummy} = $ttp->{run}{dummy};
	return $data;
}

# -------------------------------------------------------------------------------------------------
# write an execution report to a file
# the needed command is expected to be configured
# managed macros:
# - DATA
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
		my $command = $ttp->var([ 'executionReports', 'withFile', 'command' ]);
		if( $command ){
			my $json = JSON->new;
			my $str = $json->encode( $data );
			# protect the double quotes against the CMD.EXE command-line
			$str =~ s/"/\\"/g;
			$command =~ s/<DATA>/$str/;
			my $dummy = $ttp->{run}{dummy} ? "-dummy" : "-nodummy";
			my $verbose = $ttp->{run}{verbose} ? "-verbose" : "-noverbose";
			print `$command -nocolored $dummy $verbose`;
			msgVerbose( "Toops::_executionReportToFile() got $?" );
			$res = ( $? == 0 );
		} else {
			msgErr( "executionReportToFile() expected a 'command' argument, not found" );
		}
	} else {
		msgErr( "executionReportToFile() expected a 'data' argument, not found" );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# send an execution report on the MQTT bus if Toops is configured for
# managed macros:
# - SUBJECT
# - DATA
# - OPTIONS
# (I):
# - a hash ref with following keys:
#   > data, a hash ref
#   > topic, as a string
#   > options, as a string
#   > excludes, the list of data keys to be excluded
sub _executionReportToMqtt {
	my ( $args ) = @_;
	my $res = false;
	my $data = undef;
	$data = $args->{data} if exists $args->{data};
	if( defined $data ){
		$data = _executionReportCompleteData( $data );
		my $topic = undef;
		$topic = $args->{topic} if exists $args->{topic};
		my $excludes = [];
		$excludes = $args->{excludes} if exists $args->{excludes} && ref $args->{excludes} eq 'ARRAY' && scalar $args->{excludes} > 0;
		if( $topic ){
			my $dummy = $ttp->{run}{dummy} ? "-dummy" : "-nodummy";
			my $verbose = $ttp->{run}{verbose} ? "-verbose" : "-noverbose";
			my $command = $ttp->var([ 'executionReports', 'withMqtt', 'command' ]);
			if( $command ){
				foreach my $key ( keys %{$data} ){
					if( !grep( /$key/, @{$excludes} )){
						#my $json = JSON->new;
						#my $str = $json->encode( $data );
						my $cmd = $command;
						$cmd =~ s/<SUBJECT>/$topic\/$key/;
						$cmd =~ s/<DATA>/$data->{$key}/;
						my $options = $args->{options} ? $args->{options} : "";
						$cmd =~ s/<OPTIONS>/$options/;
						print `$cmd -nocolored $dummy $verbose`;
						my $rc = $?;
						msgVerbose( "Toops::_executionReportToMqtt() got rc=$rc" );
						$res = ( $rc == 0 );
					} else {
						msgVerbose( "do not publish excluded '$key' key" );
					}
				}
			} else {
				msgErr( "executionReportToMqtt() expected a 'command' argument, not found" );
			}
		} else {
			msgErr( "executionReportToMqtt() expected a 'topic' argument, not found" );
		}
	} else {
		msgErr( "executionReportToMqtt() expected a 'data' argument, not found" );
	}
	return $res;
}

# -------------------------------------------------------------------------------------------------
# exit the command
# Return code is optional, defaulting to TTPVars->{run}{exitCode}

sub exit {
	my $rc = shift || $ttp->runner()->runnableErrs();
	if( $rc ){
		msgErr( "exiting with code $rc" );
	} else {
		msgVerbose( "exiting with code $rc" );
	}
	exit $rc;
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
		push( @roots, $ttp->{run}{command}{directory} );
	}
	my @commands = glob( File::Spec->catdir( $ttp->{run}{command}{directory}, "*.pl" ));
	return @commands;
}

# -------------------------------------------------------------------------------------------------
# returns the list of defined hosts, reading the hosts configuration directory
# do not return the hosts whose configuration file is disabled
sub getDefinedHosts {
	my @hosts = ();
	my $dir = TTP::Path::hostsConfigurationsDir();
	opendir my $dh, $dir or msgErr( "cannot open '$dir' directory: $!" );
	if( !errs()){
		my @entries = readdir $dh;
		closedir $dh;
		foreach my $entry ( @entries ){
			if( $entry ne '.' && $entry ne '..' ){
				$entry =~ s/\.[^.]+$//;
				my $hash = hostConfigRead( $entry, { ignoreDisabled => true });
				push( @hosts, $entry ) if defined $hash;
			}
		}
	}
	return @hosts;
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
		$TTPVars->{evaluating} = $hash;
		my $withEvaluate = true;
		$withEvaluate = $opts->{withEvaluate} if exists $opts->{withEvaluate};
		if( $withEvaluate ){
			$hash = evaluate( $TTPVars->{evaluating} );
		}
		$TTPVars->{evaluating} = undef;
	}
	return $hash;
}

# -------------------------------------------------------------------------------------------------
# returns a new unique temp filename
sub getTempFileName {
	my $fname = $ttp->{run}{command}{name};
	$fname .= "-$ttp->{run}{verb}{name}" if $ttp->{run}{verb}{name};
	my $random = ttpRandom();
	my $tempfname = File::Spec->catdir( TTP::Path::logsDailyDir(), "$fname-$random.tmp" );
	msgVerbose( "getTempFileName() tempfname='$tempfname'" );
	return $tempfname;
}

# -------------------------------------------------------------------------------------------------
# Getter
# (I):
# - none
# (O):
# - returns the current execution node name, which may be undef very early in the process

sub host {
	my $node = $ttp->node();
	return $node ? $node->name() : undef;
}

# -------------------------------------------------------------------------------------------------
# Substitute the macros in a host configuration file
# (I):
# - the raw JSON hash
# - an options hash with following keys:
#   > host: the hostname being treated
# (O):
# - the same with substituted macros:
#   > HOST
sub hostConfigMacrosRec {
	my ( $hash, $opts ) = @_;
	my $ref = ref( $hash );
	if( $ref eq 'HASH' ){
		foreach my $key ( keys %{$hash} ){
			$hash->{$key} = hostConfigMacrosRec( $hash->{$key}, $opts );
		}
	} elsif( $ref eq 'ARRAY' ){
		my @array = ();
		foreach my $it ( @{$hash} ){
			push( @array, hostConfigMacrosRec( $it, $opts ));
		}
		$hash = \@array;
	} elsif( !$ref ){
		my $host = $opts->{host};
		$hash =~ s/<HOST>/$host/g;
	} else {
		msgVerbose( "Toops::hostConfigMacrosRec() unmanaged ref: '$ref'" );
	}
	return $hash;
}

# -------------------------------------------------------------------------------------------------
# read the host configuration without evaluation
# (I):
# - the hostname
# - an optional options hash with following keys:
#   > ignoreDisabled, defaulting to false
# (O):
# - returns the found data
#   with a new 'name' key which contains this same hostname
# or undef in case of an error
# Manage macros:
# - HOST
sub hostConfigRead {
	my ( $host, $opts ) = @_;
	$opts //= {};
	my $result = undef;
	if( !$host ){
		msgErr( "Toops::hostConfigRead() hostname expected" );
	} else {
		$result = jsonRead( TTP::Path::hostConfigurationPath( $host ));
		if( exists( $result->{enabled} ) && !$result->{enabled} ){
			my $ignoreDisabled = false;
			$ignoreDisabled = $opts->{ignoreDisabled} if exists $opts->{ignoreDisabled};
			msgErr( "Host configuration file is disabled, aborting" ) if !$ignoreDisabled;
			$result = undef;
		} else {
			$result->{name} = $host;
		}
	}
	$result = hostConfigMacrosRec( $result, { host => $host }) if defined $result;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Initialize an external script (i.e. a script which is not part of TTP, but would like take advantage of it)
# (I):
# (O):
# - TTPVars hash ref
sub initExtern {
	_bootstrap();

	# Runnable role
	#my( $vol, $dirs, $file ) = File::Spec->splitpath( $0 );
	#$ttp->{run}{command}{path} = $0;
	#$ttp->{run}{command}{started} = Time::Moment->now;
	#$ttp->{run}{command}{args} = \@ARGV;
	#$ttp->{run}{command}{basename} = $file;
	#$file =~ s/\.[^.]+$//;
	#$ttp->{run}{command}{name} = $file;
	
	$ttp->{run}{help} = scalar @ARGV ? false : true;

	return $TTPVars;
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
	msgVerbose( "jsonAppend() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	TTP::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	my $res = path( $path )->append_utf8( $str.EOL );
	msgVerbose( "jsonAppend() returns ".Dumper( $res ));
	return $res ? true : false;
}

# -------------------------------------------------------------------------------------------------
# Read a JSON file into a hash
# Do not evaluate here, just read the file data
# (I):
# - the full path to the to-be-loaded-and-interpreted json file
# - an optional options hash with following keys:
#   > ignoreIfNotExist: defaulting to false
# (O):
# returns the read hash, or undef
sub jsonRead {
	my ( $conf, $opts ) = @_;
	$opts //= {};
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
		my $ignoreIfNotExist = false;
		$ignoreIfNotExist = $opts->{ignoreIfNotExist} if exists $opts->{ignoreIfNotExist};
		msgErr( "jsonRead() $conf: not found or not readable" ) if !$ignoreIfNotExist;
	} else {
		msgErr( "jsonRead() expects a JSON path to be read" );
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
	msgVerbose( "jsonWrite() to '$path'" );
	my $json = JSON->new;
	my $str = $json->encode( $hash );
	my ( $vol, $dirs, $file ) = File::Spec->splitpath( $path );
	TTP::Path::makeDirExist( File::Spec->catdir( $vol, $dirs ));
	# some daemons may monitor this file in order to be informed of various executions - make sure each record has an EOL
	# '$res' is an array with the original path and an interpreted one - may also return true
	my $res = path( $path )->spew_utf8( $str.EOL );
	msgVerbose( "jsonWrite() returns ".Dumper( $res ));
	return (( looks_like_number( $res ) && $res == 1 ) || ( ref( $res ) eq 'Path::Tiny' && scalar( @{$res} ) > 0 )) ? true : false;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsCommands' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsCommands {
	my $result = $ttp->node() ? ( $ttp->var( 'logsCommands' ) || logsDaily()) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsDaily' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsDaily {
	my $result = $ttp->node() ? ( $ttp->var( 'logsDaily' ) || logsRoot()) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsMain' full pathname, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsMain {
	my $result = $ttp->node() ? ( $ttp->var( 'logsMain' ) || File::Spec->catfile( logsCommands(), 'main.log' )) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'logsRoot' directory, which may be undef very early in the bootstrap process
#   and at least not definitive while the node has not been instanciated/loaded/evaluated

sub logsRoot {
	my $result = $ttp->node() ? ( $ttp->var( 'logsRoot' ) || tempDir()) : undef;
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
		return true;
	}
	my $cmdres = commandByOs({
		command => $ttp->var([ 'moveDir', 'byOS', $Config{osname}, 'command' ]),
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

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'nodeRoot' directory specified in the site configuration to act as a replacement
#   to the mounted filesystem as there is no logical machine in this Perl version

sub nodeRoot {
	my $result = $ttp->site() ? ( $ttp->var( 'nodeRoot' ) || $Const->{byOS}{$Config{osname}}{tempDir} ) : undef;
	return $result;
}

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'nodesDirs' array of directories specified in the site configuration which are the
#   subdirectories of TTP_ROOTS where we can find nodes JSON configuration files.

sub nodesDirs {
	my $result = $ttp->site() ? TTP::Node->dirs() : undef;
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
	msgVerbose( "Toops::removeTree() removing '$dir'" );
	my $error;
	remove_tree( $dir, {
		verbose => $ttp->{run}{verbose},
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
	$ttp = TTP::EP->new();
	$ttp->bootstrap();
	$ttp->runCommand();
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
			TTP::searchRecArray( $it, $searched, $opts, $recData );
		} elsif( $type eq 'HASH' ){
			push( @{$recData->{path}}, '' );
			TTP::searchRecHash( $it, $searched, $opts, $recData );
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
				TTP::searchRecArray( $ref, $searched, $opts, $recData );
			} elsif( $type eq 'HASH' ){
				push( @{$recData->{path}}, $key );
				TTP::searchRecHash( $ref, $searched, $opts, $recData );
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

# ------------------------------------------------------------------------------------------------
# (I):
# - none
# (O):
# - returns the 'tempDir' directory for the running OS

sub tempDir {
	my $result = $Const->{byOS}{$Config{osname}}{tempDir};
	return $result;
}

# -------------------------------------------------------------------------------------------------
# re-evaluate both toops and (execution) host configurations
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
		$TTPVars->{config}{$key} = $TTPVars->{raw}{$key};
	}
	# then evaluate
	foreach my $key ( @{$TTPVars->{Toops}{ConfigKeys}} ){
		$TTPVars->{config}{$key} = evaluate( $TTPVars->{config}{$key} );
	}
	# and reevaluates the logs too
	$ttp->{run}{logsMain} = File::Spec->catdir( TTP::Path::logsDailyDir(), 'main.log' );
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
		push( @result, $it ) if !grep( /^\[|\(ERR|\(DUM|\(VER|\(WAR|^$/, $it ) && $it !~ /\(WAR\)/ && $it !~ /\(ERR\)/;
	}
	return \@result;
}

# -------------------------------------------------------------------------------------------------
# returns a random identifier
sub ttpRandom {
	my $ug = new Data::UUID;
	my $uuid = lc $ug->create_str();
	$uuid =~ s/-//g;
	return $uuid;
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from toops.json, maybe overriden in host configuration
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
#   each provided key (but maybe the last one) is expected to address a JSON hash object
# - an optional options hash with following keys:
#   > config: host configuration (useful when searching for a remote host), defaulting to current host config
# (O):
# - the evaluated value of this variable, which may be undef
sub TTP::var_x {
	my ( $keys, $opts ) = @_;
	$opts //= {};
	# get the toops-level result if any
	my $result = varSearch( $keys, $TTPVars->{config}{toops} );
	# get a host-level result if any searching for in currently evaluating, defaulting to execution host
	my $config = $TTPVars->{evaluating};
	$config = $TTPVars->{config}{host} if !defined $config;
	$config = $opts->{config} if exists $opts->{config};
	my $hostValue = varSearch( $keys, $config );
	# host value overrides the toops one if defined
	$result = $hostValue if defined $hostValue;
	return $result;
}

# -------------------------------------------------------------------------------------------------
# Used by verbs to access our global variables
sub TTPVars {
	return $TTPVars;
}

# -------------------------------------------------------------------------------------------------
# Returns a variable value
# This function is callable as '$ttp->var()' and is so one the preferred way of accessing
# configurations values from configuration files themselves as well as from external commands.
# (I):
# - a scalar, or an array of scalars which are to be successively searched, or an array of arrays
#   of scalars, these later being to be successively tested.
# (O):
# - the found value or undef

sub var {
	return $ttp->var( @_ );
}

# -------------------------------------------------------------------------------------------------
# returns the content of a var, read from the provided base
# (I):
# - a reference to an array of keys to be read from (e.g. [ 'moveDir', 'byOS', 'MSWin32' ])
# - the hash ref to be searched for
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
	return $ttp->{run}{dummy};
}

1;
