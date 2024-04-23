# @(#) display some daemon variables
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --[no]confdir           display the path to the directory which contains daemons configuration [${confdir}]
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use TTP::Constants qw( :all );
use TTP::Message qw( :all );
use TTP::Path;

my $TTPVars = TTP::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	confdir => 'no'};

my $opt_confdir = false;

# -------------------------------------------------------------------------------------------------
# list confdir value - e.g. 'C:\INLINGUA\configurations\daemons'
sub listConfdir {
	my $str = "confDir: ".TTP::Path::daemonsConfigurationsDir();
	msgVerbose( "returning '$str'" );
	print " $str".EOL;
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$ttp->{run}{help},
	"verbose!"			=> \$ttp->{run}{verbose},
	"colored!"			=> \$ttp->{run}{colored},
	"dummy!"			=> \$ttp->{run}{dummy},
	"confdir!"			=> \$opt_confdir )){

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
msgVerbose( "found confdir='".( $opt_confdir ? 'true':'false' )."'" );

if( !TTP::errs()){
	listConfdir() if $opt_confdir;
}

TTP::exit();
