# @(#) List available configurations
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]json              display available JSON configuration files [${json}]
#
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

use File::Spec;
use Proc::Background;

use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	colored => 'no',
	dummy => 'no',
	verbose => 'no',
	json => 'no'
};

my $opt_json = false;

# -------------------------------------------------------------------------------------------------
# display available JSON configuration files
sub doListJSON {
	msgOut( "displaying available JSON configuration files..." );
	my $json_path = TTP::Path::daemonsConfigurationsDir();
	opendir( my $dh, $json_path ) or msgErr( "opendir $json_path: $!" );
	if( !TTP::errs()){
		my $count = 0;
		my $sufixed_path = TTP::Path::withTrailingSeparator( $json_path );
		while( readdir( $dh )){
			if( $_ ne '.' && $_ ne '..' ){
				my $json = File::Spec->catpath( $sufixed_path, $_ );
				print "  $json".EOL;
				$count += 1;
			}
		}
		closedir( $dh );
		msgOut( "found $count JSON configuration files" );
	}
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"verbose!"			=> \$ttp->{run}{verbose},
	"json!"				=> \$opt_json )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $ttp->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $ttp->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $ttp->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found json='".( $opt_json ? 'true':'false' )."'" );

msgWarn( "no action as '--json' option is not set" ) if !$opt_json;

if( !TTP::errs()){
	doListJSON() if $opt_json;
}

TTP::exit();
