# @(#) publish code and configurations from development environment to pull target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --[no]check             whether to check for cleanity [${check}]
# @(-) --[no]tag               tag the git repository [${tag}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Config;
use Data::Dumper;
use File::Copy::Recursive qw( dircopy pathrmdir );
use File::Spec;
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Message qw( :all );
use Mods::Path;
use Mods::Toops;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	check => 'yes',
	tag => 'yes'
};

my $opt_check = true;
my $opt_tag = true;

# -------------------------------------------------------------------------------------------------
# publish  the reference tree to the pull target
sub doPublish {
	#my ( $pullConfig ) = @_;
	my $result = false;
	my $tohost = $TTPVars->{config}{toops}{deployments}{pullReference};
	msgOut( "publishing to '$tohost'..." );
	my $asked = 0;
	my $done = 0;
	foreach my $dir ( @{$TTPVars->{config}{toops}{deployments}{sourceDirs}} ){
		$asked += 1;
		my @dirs = File::Spec->splitdir( $dir );
		my $srcdir = File::Spec->rel2abs( File::Spec->catdir( File::Spec->curdir(), $dirs[scalar @dirs - 1] ));
		msgOut( "  to $dir" );
		msgDummy( "File::Copy::Recursive->dircopy( $srcdir, $dir )" );
		if( !Mods::Toops::wantsDummy()){
			my $res = pathrmdir( $dir );
			msgVerbose( "doPublish.pathrmdir() got rc=$res" );
			my( $num_of_files_and_dirs, $num_of_dirs, $depth_traversed ) = dircopy( $srcdir, $dir );
			msgVerbose( "num_of_files_and_dirs='$num_of_files_and_dirs'" );
			msgVerbose( "num_of_dirs='$num_of_dirs'" );
			msgVerbose( "depth_traversed='$depth_traversed'" );
		}
		$done += 1;
	}
	if( $opt_tag ){
		msgOut( "tagging the git repository" );
		my $now = localtime->strftime( '%Y%m%d_%H%M%S' );
		my $message = "$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name}";
		print `git tag -am "$message" $now`;
	}
	my $str = "$done/$asked subdirs copied";
	if( $done == $asked && !Mods::Toops::errs()){
		msgOut( "success ($str)" );
	} else {
		msgErr( "NOT OK ($str)" );
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
	"check!"			=> \$opt_check,
	"tag!"				=> \$opt_tag )){

		msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found check='".( $opt_check ? 'true':'false' )."'" );
msgVerbose( "found tag='".( $opt_tag ? 'true':'false' )."'" );

if( $opt_check ){
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
		msgErr( "must publish from 'master' branch, found '$branch'" );
	} else {
		msgVerbose( "publishing from '$branch' branch: fine" );
	}
	if( $changes ){
		msgErr( "have found uncommitted changes, but shouldn't" );
	} else {
		msgVerbose( "no uncommitted change found: fine" );
	}
	if( $untracked ){
		msgErr( "have found untracked files, but shouldn't (maybe move them to uncommitted/)" );
	} else {
		msgVerbose( "no untracked file found: fine" );
	}
	if( !$clean ){
		msgErr( "must publish from a clean working tree, but this one is not" );
	} else {
		msgVerbose( "found clean working tree: fine" );
	}
} else {
	msgWarn( "no check is made as '--check' option has been set to false" );
}

if( !Mods::Toops::errs()){
	doPublish();
}

Mods::Toops::ttpExit();
