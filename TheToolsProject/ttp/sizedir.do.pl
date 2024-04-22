# @(#) compute and publish the size of a directory content
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --dirpath=s             the source path [${dirpath}]
# @(-) --dircmd=s              the command which will give the source path [${dircmd}]
# @(-) --[no]mqtt              publish the result as a MQTT payload [${mqtt}]
# @(-) --[no]http              publish the result as a HTTP telemetry [${http}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Path qw( remove_tree );
use File::Find;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	dirpath => '',
	dircmd => '',
	mqtt => 'no',
	http => 'no'
};

my $opt_dirpath = $defaults->{dirpath};
my $opt_dircmd = $defaults->{dircmd};
my $opt_mqtt = false;
my $opt_http = false;

# global variables here
my $dirCount = 0;
my $fileCount = 0;
my $totalSize = 0;

# -------------------------------------------------------------------------------------------------
# receive here all found files in the searched directories
# According to https://perldoc.perl.org/File::Find
#   $File::Find::dir is the current directory name,
#   $_ is the current filename within that directory
#   $File::Find::name is the complete pathname to the file.
sub compute {
	$dirCount += 1 if -d $File::Find::name;
	$fileCount += 1 if -f $File::Find::name;
	$totalSize += -s if -f $File::Find::name;
}

# -------------------------------------------------------------------------------------------------
# Compute the size of a directory content
sub doComputeSize {
	msgOut( "computing the '$opt_dirpath' content size" );
	find ( \&compute, $opt_dirpath );
	msgOut( "  directories: $dirCount" );
	msgOut( "  files: $fileCount" );
	msgOut( "  size: $totalSize" );
	my $code = 0;
	if( $opt_mqtt || $opt_http ){
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		my $path = $opt_dirpath;
		$path =~ s/[:\/\\]+/_/g;
		my $withMqtt = $opt_mqtt ? "-mqtt" : "-nomqtt";
		my $withHttp = $opt_http ? "-http" : "-nohttp";
		print `telemetry.pl publish -metric dirs_count -value $dirCount -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose $withMqtt $withHttp`;
		$code += $?;
		print `telemetry.pl publish -metric files_count -value $fileCount -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose $withMqtt $withHttp`;
		$code += $?;
		print `telemetry.pl publish -metric content_size -value $totalSize -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose $withMqtt $withHttp`;
		$code += $?;
	}
	if( $code ){
		msgErr( "NOT OK" );
	} else {
		msgOut( "success" );
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
	"dirpath=s"			=> \$opt_dirpath,
	"dircmd=s"			=> \$opt_dircmd,
	"mqtt!"				=> \$opt_mqtt,
	"http!"				=> \$opt_http )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		ttpExit( 1 );
}

if( TTP::wantsHelp()){
	TTP::helpVerb( $defaults );
	ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found dirpath='$opt_dirpath'" );
msgVerbose( "found dircmd='$opt_dircmd'" );
msgVerbose( "found mqtt='".( $opt_mqtt ? 'true':'false' )."'" );
msgVerbose( "found http='".( $opt_http ? 'true':'false' )."'" );

# dircmd and dirpath options are not compatible
my $count = 0;
$count += 1 if $opt_dirpath;
$count += 1 if $opt_dircmd;
msgErr( "one of '--dirpath' and '--dircmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path and make it exist to be sure to have something to publish
$opt_dirpath = TTP::Path::fromCommand( $opt_dircmd, { makeExist => true }) if $opt_dircmd;

if( !ttpErrs()){
	doComputeSize();
}

ttpExit();
