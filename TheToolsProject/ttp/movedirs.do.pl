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
# @(-) --[no]dirs              move only directories and their content [${dirs}]
# @(-) --keep=s                count of to-be-kept directories in the source [${keep}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Spec;

use Mods::Path;

my $TTPVars = Mods::Toops::TTPVars();

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
	Mods::Toops::msgOut( "moving from '$opt_sourcepath' to '$opt_targetpath', keeping '$opt_keep' item(s)" );
	my $count = 0;
	opendir( FD, "$opt_sourcepath" ) || Mods::Toops::msgErr( "unable to open directory $opt_sourcepath: $!" );
	if( !Mods::Toops::errs()){
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
		Mods::Path::makeDirExist( $opt_targetpath );
		foreach my $it ( @list ){
			my $source = _sourcePath( $it );
			my $target = _targetPath( $it );
			Mods::Toops::msgOut( " moving '$source' to '$target'" );
			my $res = Mods::Toops::moveDir( $source, $target );
			if( $res ){
				$count += 1;
			} else {
				Mods::Toops::msgErr( "error detected" );
			}
		}
	}
	Mods::Toops::msgOut( "$count moved directory(ies)" );
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
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"sourcepath=s"		=> \$opt_sourcepath,
	"sourcecmd=s"		=> \$opt_sourcecmd,
	"targetpath=s"		=> \$opt_targetpath,
	"targetcmd=s"		=> \$opt_targetcmd,
	"dirs!"				=> \$opt_dirs,
	"keep=s"			=> \$opt_keep )){

		Mods::Toops::msgOut( "try '$TTPVars->{run}{command}{basename} $TTPVars->{run}{verb}{name} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found sourcepath='$opt_sourcepath'" );
Mods::Toops::msgVerbose( "found sourcecmd='$opt_sourcecmd'" );
Mods::Toops::msgVerbose( "found targetpath='$opt_targetpath'" );
Mods::Toops::msgVerbose( "found targetcmd='$opt_targetcmd'" );
Mods::Toops::msgVerbose( "found dirs='".( $opt_dirs ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found keep='$opt_keep'" );

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
$opt_sourcepath = Mods::Toops::pathFromCommand( $opt_sourcecmd, { mustExists => true }) if $opt_sourcecmd;

# if we have a target cmd, get the path
$opt_targetpath = Mods::Toops::pathFromCommand( $opt_targetcmd ) if $opt_targetcmd;

# --dirs option must be specified at the moment
msgErr( "--dirs' option must be specified (at the moment)" ) if !$opt_dirs;

if( !Mods::Toops::errs()){
	doMoveDirs();
}

Mods::Toops::ttpExit();
