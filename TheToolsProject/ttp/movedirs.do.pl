# @(#) move directories from a source to a target
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run [${dummy}]
# @(-) --sourcepath=s          the source path [${sourcepath}]
# @(-) --sourcecmd=s           the command which will give the source path [${sourcecmd}]
# @(-) --targetpath=s          the target path [${targetpath}]
# @(-) --targetcmd=s           the command which will give the target path [${targetcmd}]
# @(-) --[no]dirs              move directories and their content [${dirs}]
# @(-) --keep=s                count of to-be-kept directories in the source [${keep}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	sourcepath => '',
	sourcecmd => '',
	targetpath => '',
	targetcmd => '',
	dirs => 'no',
	keep => '0'
};

my $opt_sourcepath = $defaults->{sourcepath};
my $opt_sourcecmd = $defaults->{sourcecmd};
my $opt_targetpath = $defaults->{targetpath};
my $opt_targetcmd = $defaults->{targetcmd};
my $opt_dirs = false;
my $opt_keep = $defaults->{keep};

# -------------------------------------------------------------------------------------------------
# Move directories from source to target, only keeping some in source
# - ignore dot files and dot dirs
# - ignore files, only considering dirs
sub doMoveDirs {
	msgOut( "moving from '$opt_sourcepath' to '$opt_targetpath', keeping '$opt_keep' item(s)" );
	my $count = 0;
	if( -d $opt_sourcepath ){
		opendir( FD, "$opt_sourcepath" ) || msgErr( "unable to open directory $opt_sourcepath: $!" );
		if( !TTP::errs()){
			my @list = ();
			while ( my $it = readdir( FD )){
				my $path = _sourcePath( $it );
				if( $it =~ /^\./ ){
					msgVerbose( "ignoring '$path'" );
					next;
				}
				if( $opt_dirs && -d "$path" ){
					push( @list, "$it" );
					next;
				}
				msgVerbose( "ignoring '$path'" );
			}
			closedir( FD );
			# sort in inverse order: most recent first
			@list = sort { $b cmp $a } @list;
			msgVerbose( "got ".scalar @list." item(s) in $opt_sourcepath" );
			# build the lists to be kept and moved
			my @keep = ();
			if( $opt_keep >= scalar @list ){
				msgOut( "found ".scalar @list." item(s) in '$opt_sourcepath' while wanting keep $opt_keep: nothing to do" );
				@keep = @list;
				@list = ();
			} elsif( !$opt_keep ){
					msgVerbose( "keep='$opt_keep': doesn't keep anything in the source" );
			} else {
				for( my $i=0 ; $i<$opt_keep ; ++$i ){
					my $it = shift( @list );
					msgVerbose( "keeping "._sourcePath( $it ));
					push( @keep, $it );
				}
			}
			# and move the rest, making sure the initial path at least exists
			TTP::Path::makeDirExist( $opt_targetpath );
			foreach my $it ( @list ){
				my $source = _sourcePath( $it );
				my $target = _targetPath( $it );
				msgOut( " moving '$source' to '$target'" );
				my $res = TTP::moveDir( $source, $target );
				if( $res ){
					$count += 1;
				} else {
					msgErr( "error detected" );
				}
			}
		}
	} else {
		msgOut( "'$opt_sourcepath' doesn't exist: nothing to move" );
	}
	msgOut( "$count moved directory(ies)" );
}

sub _sourcePath {
	my ( $it ) = @_;
	return File::Spec->catdir( $opt_sourcepath, $it );
}

sub _targetPath {
	my ( $it ) = @_;
	return File::Spec->catdir( $opt_targetpath, $it );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"verbose!"			=> \$ttp->{run}{verbose},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"sourcepath=s"		=> \$opt_sourcepath,
	"sourcecmd=s"		=> \$opt_sourcecmd,
	"targetpath=s"		=> \$opt_targetpath,
	"targetcmd=s"		=> \$opt_targetcmd,
	"dirs!"				=> \$opt_dirs,
	"keep=s"			=> \$opt_keep )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found sourcepath='$opt_sourcepath'" );
msgVerbose( "found sourcecmd='$opt_sourcecmd'" );
msgVerbose( "found targetpath='$opt_targetpath'" );
msgVerbose( "found targetcmd='$opt_targetcmd'" );
msgVerbose( "found dirs='".( $opt_dirs ? 'true':'false' )."'" );
msgVerbose( "found keep='$opt_keep'" );

# sourcecmd and sourcepath options are not compatible
my $count = 0;
$count += 1 if $opt_sourcepath;
$count += 1 if $opt_sourcecmd;
msgErr( "one of '--sourcepath' and '--sourcecmd' options must be specified" ) if $count != 1;

# targetcmd and targetpath options are not compatible
$count = 0;
$count += 1 if $opt_targetpath;
$count += 1 if $opt_targetcmd;
msgErr( "one of '--targetpath' and '--targetcmd' options must be specified" ) if $count != 1;

# if we have a source cmd, get the path and check it exists
# no need to make the dir exist: if not exist, then there is just nothing to move
$opt_sourcepath = TTP::Path::fromCommand( $opt_sourcecmd ) if $opt_sourcecmd;

# if we have a target cmd, get the path
$opt_targetpath = TTP::Path::fromCommand( $opt_targetcmd ) if $opt_targetcmd;

# --dirs option must be specified at the moment
msgErr( "--dirs' option must be specified (at the moment)" ) if !$opt_dirs;

if( !TTP::errs()){
	doMoveDirs();
}

TTP::exit();
