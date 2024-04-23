# @(#) list various TTP objects
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]commands          list the available commands [${commands}]
# @(-) --[no]nodes             list the available nodes [${nodes}]
# @(-) --[no]services          list the defined services on this host [${services}]
#
# The Tools Project: a Tools System and Paradigm for IT Production
# Copyright (©) 2003-2023 Pierre Wieser (see AUTHORS)
# Copyright (©) 2024 PWI Consulting
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

use Config;

use TTP::Command;
use TTP::Node;
use TTP::Service;

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	commands => 'no',
	nodes => 'no',
	services => 'no'
};

my $opt_commands = false;
my $opt_nodes = false;
my $opt_services = false;

# -------------------------------------------------------------------------------------------------
# list the available commands

sub listCommands {
	msgOut( "displaying available commands..." );
	# list all commands in all TTP_ROOTS trees
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $const = TTP::Command->finder();
	my @commands = ();
	foreach my $it ( @roots ){
		my $dir = File::Spec->catdir( $it, $const->{dir} );
		push @commands, glob( File::Spec->catdir( $dir, $const->{sufix} ));
	}
	# get only unique commands
	my $uniqs = {};
	my $count = 0;
	foreach my $it ( @commands ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		$uniqs->{$file} = $it if !exists( $uniqs->{$file} );
	}
	# and display them in ascii order
	foreach my $it ( sort keys %{$uniqs} ){
		TTP::Command::helpOneline( $uniqs->{$it}, { prefix => ' ' });
		$count += 1;
	}
	msgOut( "$count found command(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the available nodes

sub listNodes {
	msgOut( "displaying available nodes..." );
	# list all nodes in all TTP_ROOTS trees
	my @roots = split( /$Config{path_sep}/, $ENV{TTP_ROOTS} );
	my $dirs = TTP::Node->finder();
	my @nodes = ();
	foreach my $it ( @roots ){
		foreach my $dir ( @{$dirs} ){
			my $nodedir = File::Spec->catdir( $it, $dir );
			push @nodes, glob( File::Spec->catfile( $nodedir, '*.json' ));
		}
	}
	# get only unique available nodes
	my $uniqs = {};
	my $count = 0;
	foreach my $it ( @nodes ){
		my ( $vol, $dirs, $file ) = File::Spec->splitpath( $it );
		my $name = $file;
		$name =~ s/\.[^\.]+$//;
		my $node = TTP::Node->new( $ttp, { node => $name, abortOnError => false });
		$uniqs->{$name} = $it if !exists( $uniqs->{$name} ) && $node->success();
	}
	# and display them in ascii order
	foreach my $it ( sort keys %{$uniqs} ){
		print " $it".EOL;
		$count += 1;
	}
	msgOut( "$count found node(s)" );
}

# -------------------------------------------------------------------------------------------------
# list the defined services
# note: this is  design decision that this sort of display at the beginning and at the end of the verb
# execution must be done in the verb script.
# in this particular case of listing services, which is handled both as services.pl list and as ttp.pl list,
# this code is so duplicated..
sub listServices {
	my $hostConfig = TTP::getHostConfig();
	msgOut( "displaying services defined on $hostConfig->{name}..." );
	my @list = TTP::Service::getDefinedServices( $hostConfig );
	foreach my $it ( @list ){
		print " $it".EOL;
	}
	msgOut( scalar @list." found defined service(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"commands!"			=> \$opt_commands,
	"nodes!"			=> \$opt_nodes,
	"services!"			=> \$opt_services )){

		msgOut( "try '".$running->command()." ".$running->verb()." --help' to get full usage syntax" );
		TTP::exit( 1 );
}

if( $running->help()){
	$running->verbHelp( $defaults );
	TTP::exit();
}

msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
msgVerbose( "found commands='".( $opt_commands ? 'true':'false' )."'" );
msgVerbose( "found nodes='".( $opt_nodes ? 'true':'false' )."'" );
msgVerbose( "found services='".( $opt_services ? 'true':'false' )."'" );

if( !TTP::errs()){
	listCommands() if $opt_commands;
	listNodes() if $opt_nodes;
	listServices() if $opt_services;
}

TTP::exit();
