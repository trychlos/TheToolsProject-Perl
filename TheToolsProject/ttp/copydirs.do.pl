# @(#) copy directories from a source to a target
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
	dirs => 'no'
};

my $opt_sourcepath = $defaults->{sourcepath};
my $opt_sourcecmd = $defaults->{sourcecmd};
my $opt_targetpath = $defaults->{targetpath};
my $opt_targetcmd = $defaults->{targetcmd};
my $opt_dirs = false;

# -------------------------------------------------------------------------------------------------
# Copy directories from source to target
sub doCopyDirs {
	Mods::Toops::msgOut( "copying from '$opt_sourcepath' to '$opt_targetpath'..." );
	my $count = 0;
=pod
	my $result = undef;
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
		# copy all, making sure the initial path at least exists
		$result = Mods::Path::makeDirExist( $opt_targetpath );
		if( $result ){
			foreach my $it ( @list ){
				my $source = _sourcePath( $it );
				my $target = _targetPath( $it );
				Mods::Toops::msgOut( "  copying '$source' to '$target'" );
			}
		}
	}
=cut
	my $res = Mods::Toops::copyDir( $opt_sourcepath, $opt_targetpath );
	if( $res ){
		$count += 1;
		Mods::Toops::msgOut( "$count copied directory(ies)" );
	} else {
		Mods::Toops::msgErr( "NOT OK" );
	}
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
	"dirs!"				=> \$opt_dirs )){

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
	doCopyDirs();
}

Mods::Toops::ttpExit();
