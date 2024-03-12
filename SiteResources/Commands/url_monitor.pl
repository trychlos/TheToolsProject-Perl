#!/usr/bin/perl
# @(#) Monitor the services URLs
#
# This script is run from an external (Linux) monitoring host in a crontab, so cannot take advantage of TTP.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;
use File::Basename;
use Getopt::Long;

use constant { true => 1, false => 0 };

my $me = basename( $0 );
my $nbopts = scalar @ARGV;

my $defaults = {
	help => 'no',
	service => ''
};

my $opt_help = false;
my $opt_service = $defaults->{service};

# the list of to-be-monitored services
my @services = ();

# -------------------------------------------------------------------------------------------------
# 
sub msgHelp {
	print "Monitor the services URL's
  Usage: $0 [options]
  where available options are:
    --[no]help              print this message, and exit [$defaults->{help}]
    --service=<name>        the service to be monitored, may be specified several times or as a comma-separated list [$defaults->{service}]
";
}

# -------------------------------------------------------------------------------------------------
# 
sub msgAlert {
	msgOut( @_ );
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
	"service=s@"		=> \$opt_service )){

		msgOut( "try '$0 --help' to get full usage syntax" );
		exit( 1 );
}

$opt_help = true if !$nbopts;

if( $opt_help ){
	msgHelp();
	exit( 0 );
}

msgVerbose( "found help='".( $opt_help ? 'true':'false' )."'" );
@services = split( /,/, join( ',', @{$opt_service} ));
msgVerbose( "found services='".join( ',', @services )."'" );

foreach my $service ( @services ){
	msgVerbose( "new service $service" );

	# get the list of hosts which hold the production of this service
	# [services.pl list] displaying machines which provide \'Canal33\' service in \'X\' environment...
	#    X: NS230134
	#    X: WS12PROD1
	# [services.pl list] 2 found machine(s)
	my $stdout = `services.pl list -nocolored -service $service -type X -machines`;
	my @lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
	my @hosts = ();
	foreach my $it ( @lines ){
		my @words = split( /\s+/, $it );
		push( @hosts, $words[2] );
		msgVerbose( "pushing host $words[2]" );
	}

	# we expect that each host of this same service has the same canonical url in its configuration file
	# so examines the configurations until having found a non-empty url
	# we stop at the first found, hoping that other(s) url(s) are the exact same
	my $url = "";
	foreach my $host ( @hosts ){
		if( !$url ){
			msgVerbose( "trying $host" );
			$stdout = `ssh inlingua-user\@$host services.pl vars -nocolored -service $service -key url`;
			@lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
			my @words = split( /\s+/, $lines[0] );
			$url = $words[1];

			# when we have found an url, test it to get the live host server
			if( $url ){
				$stdout = `http.pl get -nocolored -url $url -header X-Sent-By -ignore`;
				@lines = grep( !/^\[|\(WAR\)/, split( /[\r\n]/, $stdout ));
				my $status = scalar( @lines ) ? '1' : '0' ;
				my $live = '';
				my $next = '';
				if( $status ){
					@words = split( /\s+/, $lines[0] );
					$live = $words[1];
				} else {
					my @others = grep( !/$host/, @hosts );
					$next = $others[0];
				}
				# publish something to the telemetry
				my $live_label = "-label live=$live" if $live;
				my $next_label = "-label next=$next" if $next;
				`ssh inlingua-user\@$host telemetry.pl publish -metric status -label service=$service -label url=$url $live_label $next_label -value=$status -httpPrefix ttp_live_ -mqttPrefix live/`;

				# if the url didn't answer, then alert
				if( !$status ){
					`ssh inlingua-user\@$host ttp.pl alert -level ALERT -message "URL DIDN'T ANSWER
Service: $service
Next: $next
Run: 'url_switch.pl -service $service -to $next'"`;
				}
			} else {
				msgVerbose( "url not found" );
			}
		} else {
			msgVerbose( "no need to request $host as url has already been found" );
		}
	}
	if( !$url ){
		msgAlert( "service $service has no defined url" );
	}
}
