# Copyright (@) 2023-2024 PWI Consulting
#
# Various paths management
#
# The integrator must configure:
#
# - as environment variables:
#
#   > TTP_SITE: as the path to the tree which contains all configurations files, and specially 'toops.json'
#     it is suggested that this configuration tree be outside of the Toops installation
#     it is addressed by siteConfigurationsDir()
#     the structure is fixed at the moment:
#
#       TTP_SITE/
#        |
#        +- toops.json
#            |
#            +- daemons/
#            |
#            +- machines/
#
# - in toops.json:
#
#   > logsRoot: the root of the logs tree
#     is is addressed by logsRootDir()
#     this package takes care of creating it if it doesn't exist yet

package Mods::Path;

use strict;
use warnings;

use Data::Dumper;
use File::Spec;
use Sys::Hostname qw( hostname );
use Time::Piece;

use Mods::Constants qw( :all );
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
sub daemonsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "daemons" );
}

# ------------------------------------------------------------------------------------------------
sub hostsConfigurationsDir {
	return File::Spec->catdir( siteConfigurationsDir(), "machines" );
}

# ------------------------------------------------------------------------------------------------
sub siteConfigurationsDir {
	return $ENV{TTP_SITE};
}

# ------------------------------------------------------------------------------------------------
sub logsRootDir {
	my $TTPVars = Mods::Toops::TTPVars();
	my $dir = $TTPVars->{config}{site}{toops}{logsRoot};
	Mods::Toops::msgErr( "siteLogsRootDir() 'logsRoot' value is not set, but is required" ) if $dir;
	makeDirExist( $dir );
	return $dir;
}

# -------------------------------------------------------------------------------------------------
# make sure a directory exist
# returns true|false
sub makeDirExist {
	my ( $dir ) = @_;
	my $result = false;
	if( -d $dir ){
		Mods::Toops::msgVerbose( "Toops::makeDirExist() dir='$dir' already exists" );
		$result = true;
	# seems that make_path is not easy with UNC path (actually seems that make_path just dies)
	} elsif( $dir =~ /^\\\\/ ){
		Mods::Toops::msgVerbose( "Toops::makeDirExist() dir='$dir' is a UNC path, recursing by level" );
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
			$result &= Mods::Toops::msgDummy( "mkdir $dir" );
			if( !Mods::Toops::wantsDummy()){
				$result &= mkdir $dir;
			}
			$candidate = File::Spec->catdir(  $candidate, $level );
		}
	} else {
		Mods::Toops::msgVerbose( "Toops::makeDirExist() dir='$dir' tries make_path()" );
		$result &= Mods::Toops::msgDummy( "make_path( $dir )" );
		if( !Mods::Toops::wantsDummy()){
			my $error;
			make_path( $dir, {
				verbose => Mods::Toops::TTPVars()->{run}{verbose},
				error => \$error
			});
			# https://perldoc.perl.org/File::Path#make_path%28-%24dir1%2C-%24dir2%2C-....-%29
			if( $error && @$error ){
				for my $diag ( @$error ){
					my ( $file, $message ) = %$diag;
					if( $file eq '' ){
						Mods::Toops::msgErr( $message );
					} else {
						Mods::Toops::msgErr( "$file: $message" );
					}
				}
				$result = false;
			}
		}
	}
	Mods::Toops::msgVerbose( "Toops::makeDirExist() dir='$dir' result=$result" );
	return $result;
}

# ------------------------------------------------------------------------------------------------
sub toopsConfigurationPath {
	return File::Spec->catdir( siteConfigurationsDir(), 'toops.json' );
}

1;
