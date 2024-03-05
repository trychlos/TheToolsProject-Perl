# Copyright (@) 2023-2024 PWI Consulting
#
# SMTP gateway management.
#
# We expect find in configuration:
# - an email host server to connect to, with an account and a password
# - a default sender
#
# We expect be provided
# - subject, mailto, content

package Mods::SMTP;

use strict;
use warnings;

use Data::Dumper;
use Email::Stuffer;
use Email::Sender::Transport::SMTP;
use Sys::Hostname qw( hostname );
use Try::Tiny;

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# send a mail through the addressed SMTP gateway
# (I):
# - a hashref with following keys:
#   > subject
#   > text for text body, may be empty
#   > html for HTML body, may be empty
#   > to as a string or an array ref of target addresses
#   > from, defaulting to the smtp gateway 'mailfrom' default sender, which itself defaults to 'me@localhost'
#   > debug: defaulting to the smtp gateway 'debug' property, which itself defaults to false
# (O):
# - returns true|false
sub send {
	my ( $msg ) = @_;
	my $res = false;
	Mods::Message::msgErr( "Mail::send() expect parms as a hashref, not found" ) if !$msg || ref( $msg ) ne 'HASH';
	Mods::Message::msgErr( "Mail::send() expect subject, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{subject};
	Mods::Message::msgErr( "Mail::send() expect a content, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{text} && !$msg->{html};
	Mods::Message::msgErr( "Mail::send() expect at least one target email address, not found" ) if $msg && ref( $msg ) eq 'HASH' && !$msg->{to};
	my $gateway = undef;
	if( !Mods::Toops::errs()){
		$gateway = Mods::Toops::var([ 'SMTPGateway' ]);
		Mods::Message::msgErr( "Mail::send() expect smtp gateway, not found" ) if !$gateway;
		Mods::Message::msgErr( "Mail::send() password is mandatory if a username is specified" ) if $gateway && $gateway->{username} && !$gateway->{password};
	}
	if( !Mods::Toops::errs()){
		my $sender = 'me@localhost';
		$sender = $gateway->{mailfrom} if exists $gateway->{mailfrom};
		$sender = $msg->{from} if exists $msg->{from};

		my $email = Email::Stuffer->new({
			from => $sender,
			to => $msg->{to},
			subject => $msg->{subject}
		});
		$email->text_body( $msg->{text} ) if $msg->{text};
		$email->html_body( $msg->{html} ) if $msg->{html};

		my $debug = false;
		$debug = $gateway->{debug} if exists $gateway->{debug};
		$debug = $msg->{debug} if exists $msg->{debug} && defined $msg->{debug};

		# Email::Sender::Transport::SMTP is able to choose a default port if we set the 'ssl' option to 'ssl' or true
		# but is not able to set a default ssl option starting from the port - fix that here
		my $opts = {};
		$opts->{host} = $gateway->{host} || 'localhost';
		$opts->{port} = $gateway->{port} if $gateway->{port};
		#$opts->{sasl_authenticator} = $sasl;
		$opts->{sasl_username} = $gateway->{username} if $gateway->{username};
		$opts->{sasl_password} = $gateway->{password} if $gateway->{username};
		$opts->{helo} = $gateway->{helo} || uc hostname;
		$opts->{ssl} = $gateway->{security} if $gateway->{security};
		if( $gateway->{port} && !$gateway->{security} ){
			$opts->{ssl} = 'ssl' if $gateway->{port} == 465;
			$opts->{ssl} = 'starttls' if $gateway->{port} == 587;
		}
		$opts->{timeout} = $gateway->{timeout} || 60;
		$opts->{debug} = $debug;
		$opts->{ssl_options} = { SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE };
		my $transport = Email::Sender::Transport::SMTP->new( $opts );
		$email->transport( $transport );

		try {
			$res = $email->send();
		} catch {
			Mods::Message::msgWarn( "Mail::send() $!" );
			print Dumper( $res );
		};
	}
	return $res;
}

1;
