# @(#) compute and publish the size of a directory content
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --dirpath=s             the source path [${dirpath}]
# @(-) --dircmd=s              the command which will give the source path [${dircmd}]
# @(-) --[no]telemetry         whether to publish the result as a telemetry [${telemetry}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Path qw( remove_tree );
use File::Find;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Path;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	dirpath => '',
	dircmd => '',
	telemetry => 'no'
};

my $opt_dirpath = $defaults->{dirpath};
my $opt_dircmd = $defaults->{dircmd};
my $opt_telemetry = false;

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
	Mods::Message::msgOut( "computing the '$opt_dirpath' content size" );
	find ( \&compute, $opt_dirpath );
	Mods::Message::msgOut( "  $dirCount directory(ies), $fileCount file(s)" );
	Mods::Message::msgOut( "  total size: $totalSize byte(s)" );
	my $code = 0;
	if( $opt_telemetry ){
		my $dummy = $opt_dummy ? "-dummy" : "-nodummy";
		my $verbose = $opt_verbose ? "-verbose" : "-noverbose";
		my $path = $opt_dirpath;
		$path =~ s/[:\/\\]+/_/g;
		print `telemetry.pl publish -metric dirs_count -value $dirCount -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose`;
		$code += $?;
		print `telemetry.pl publish -metric files_count -value $fileCount -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose`;
		$code += $?;
		print `telemetry.pl publish -metric content_size -value $totalSize -label path=$path -httpPrefix ttp_filesystem_sizedir_ -mqttPrefix sizedir/ -nocolored $dummy $verbose`;
		$code += $?;
	}
	if( $code ){
		Mods::Message::msgErr( "NOT OK" );
	} else {
		Mods::Message::msgOut( "success" );
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
	"telemetry!"		=> \$opt_telemetry )){

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
Mods::Message::msgVerbose( "found dirpath='$opt_dirpath'" );
Mods::Message::msgVerbose( "found dircmd='$opt_dircmd'" );
Mods::Message::msgVerbose( "found telemetry='".( $opt_telemetry ? 'true':'false' )."'" );

# dircmd and dirpath options are not compatible
my $count = 0;
$count += 1 if $opt_dirpath;
$count += 1 if $opt_dircmd;
Mods::Message::msgErr( "one of '--dirpath' and '--dircmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path and check it exists
$opt_dirpath = Mods::Path::fromCommand( $opt_dircmd, { mustExists => true }) if $opt_dircmd;

if( !Mods::Toops::errs()){
	doComputeSize();
}

Mods::Toops::ttpExit();
