# @(#) Switch a service to another host
#
# This script is run from an external (Linux) monitoring host, so cannot take advantage of TTP.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Basename;
use Getopt::Long;

use constant { true => 1, false => 0 };

my $me = basename( $0 );
my $nbopts = scalar @ARGV;
my $nberrs = 0;

my $defaults = {
	help => 'no',
	service => '',
	to => ''
};

my $opt_help = false;
my $opt_service = $defaults->{service};
my $opt_to = $defaults->{to};

# -------------------------------------------------------------------------------------------------
# 
sub msgErr {
	my ( $msg ) = @_;
	print STDERR "$msg\n";
	$nberrs += 1;
}

# -------------------------------------------------------------------------------------------------
# 
sub msgHelp {
	print "Switch a service to another host
  Usage: $0 [options]
  where available options are:
    --[no]help              print this message, and exit [$defaults->{help}]
    --service=<name>        the service to be switched [$defaults->{service}]
    --to=<name>             the machine to switch to [$defaults->{to}]
";
}

# -------------------------------------------------------------------------------------------------
# 
sub msgOut {
	my ( $msg ) = @_;
	if( !ref $msg ){
		print "$msg\n";
	} elsif( ref $msg eq 'ARRAY' ){
		foreach my $it ( @{$msg} ){
			msgOut( $it );
		}
	}
}

# -------------------------------------------------------------------------------------------------
# 
sub msgVerbose {
	msgOut( @_ );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$opt_help,
	"service=s"			=> \$opt_service,
	"to=s"				=> \$opt_to )){

		msgOut( "try '$0 --help' to get full usage syntax" );
		exit( 1 );
}

$opt_help = true if !$nbopts;

if( $opt_help ){
	msgHelp();
	exit( 0 );
}

msgVerbose( "found help='".( $opt_help ? 'true':'false' )."'" );
msgVerbose( "found service='$opt_service'" );
msgVerbose( "found to='$opt_to'" );

msgErr( "'--service' option is mandatory but has not been found" ) if !$opt_service;
msgErr( "'--to' option is mandatory but has not been found" ) if !$opt_to;
exit( $nberrs ) if $nberrs;


# get the list of hosts which hold the production of this service
# [services.pl list] displaying machines which provide \'Canal33\' service in \'X\' environment...
#    X: NS230134
#    X: WS12PROD1
# [services.pl list] 2 found machine(s)
my $stdout = `services.pl list -nocolored -service $opt_service -type X -machines`;
my @lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
my @hosts = ();
foreach my $it ( @lines ){
	my @words = split( /\s+/, $it );
	push( @hosts, $words[2] );
	msgVerbose( "got $words[2]" );
}

# VERY IMPORTANT
# first task is to disable the backup daemons and the backup scheduled tasks on the target host
$stdout = `ssh inlingua-user\@$opt_to mswin.pl scheduled -task \\Inlingua -list` ;
@lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
print Dumper( @lines );

# and then switch the ip service
