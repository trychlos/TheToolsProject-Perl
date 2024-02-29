# @(#) publish code and configurations from development environment to pull target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Config;
use Data::Dumper;
use File::Copy::Recursive qw( dircopy );
use File::Spec;

use Mods::Constants qw( :all );
use Mods::Path;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no'
};

# -------------------------------------------------------------------------------------------------
# publish  the reference tree to the pull target
sub doPublish {
	#my ( $pullConfig ) = @_;
	my $result = false;
	my $tohost = $TTPVars->{config}{toops}{deployments}{pullReference};
	Mods::Message::msgOut( "publishing to '$tohost'..." );
	my $asked = 0;
	my $done = 0;
	foreach my $dir ( @{$TTPVars->{config}{toops}{deployments}{sourceDirs}} ){
		$asked += 1;
		my @dirs = File::Spec->splitdir( $dir );
		my $srcdir = File::Spec->rel2abs( File::Spec->catdir( File::Spec->curdir(), $dirs[scalar @dirs - 1] ));
		Mods::Message::msgOut( "  to $dir" );
		Mods::Message::msgDummy( "File::Copy::Recursive->dircopy( $srcdir, $dir )" );
		if( !Mods::Toops::wantsDummy()){
			my( $num_of_files_and_dirs, $num_of_dirs, $depth_traversed ) = dircopy( $srcdir, $dir );
			Mods::Message::msgVerbose( "num_of_files_and_dirs='$num_of_files_and_dirs'" );
			Mods::Message::msgVerbose( "num_of_dirs='$num_of_dirs'" );
			Mods::Message::msgVerbose( "depth_traversed='$depth_traversed'" );
		}
		$done += 1;
	}
	my $str = "$done/$asked subdirs copied";
	if( $done == $asked && !Mods::Toops::errs()){
		Mods::Message::msgOut( "success ($str)" );
	} else {
		Mods::Message::msgErr( "NOT OK ($str)" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy} )){

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

# must publish a clean development environment from master branch
my $status = `git status`;
my @status = split( /[\r\n]/, $status );
my $branch = '';
my $changes = false;
my $untracked = false;
my $clean = false;
foreach my $line ( @status ){
	if( $line =~ /^On branch/ ){
		$branch = $line;
		$branch =~ s/^On branch //;
	}
	if( $line =~ /working tree clean/ ){
		$clean = true;
	}
	# either changes not staged or changes to be committed
	if( $line =~ /^Changes / ){
		$changes  = true;
	}
	if( $line =~ /^Untracked files:/ ){
		$untracked  = true;
	}
}
if( $branch ne 'master' ){
	Mods::Message::msgErr( "must publish from 'master' branch, found '$branch'" );
} else {
	Mods::Message::msgVerbose( "publishing from '$branch' branch: fine" );
}
if( $changes ){
	Mods::Message::msgErr( "have found uncommitted changes, but shouldn't" );
} else {
	Mods::Message::msgVerbose( "no uncommitted change found: fine" );
}
if( $untracked ){
	Mods::Message::msgErr( "have found untracked files, but shouldn't (maybe move them to uncommitted/)" );
} else {
	Mods::Message::msgVerbose( "no untracked file found: fine" );
}
if( !$clean ){
	Mods::Message::msgErr( "must publish from a clean working tree, but this one is not" );
} else {
	Mods::Message::msgVerbose( "found clean working tree: fine" );
}

if( !Mods::Toops::errs()){
	doPublish();
}

Mods::Toops::ttpExit();
