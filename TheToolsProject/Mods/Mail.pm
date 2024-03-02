# Copyright (@) 2023-2024 PWI Consulting
#
# Mail management.
#
# We expect find in configuration:
# - an email host server to connect to, with an account and a password
# - a default sender
#
# We expect be provided
# - subject, mailto, content

package Mods::Mail;

use strict;
use warnings;

use Data::Dumper;
use Email::MIME;
use Email::Sender::Simple qw( sendmail );
use Email::Sender::Transport::SMTP;
use Sys::Hostname qw( hostname );

use Mods::Constants qw( :all );
use Mods::Message;
use Mods::Toops;

# ------------------------------------------------------------------------------------------------
# send a mail through the addressed SMTP gateway
# (I):
# - a message with following keys:
#   > subject
#   > message as an array ref of target addresses
#   > mailto
# - the smtp gateway properties
# (O):
# - returns true|false
sub send {
	my ( $msg, $gateway ) = @_;
	Mods::Message::msgErr( "expect message, not found" ) if !$msg;
	Mods::Message::msgErr( "expect smtp gateway, not found" ) if !$gateway;
	Mods::Message::msgErr( "password is mandatory if a username is specified" ) if $gateway && $gateway->{username} && !$gateway->{password};
	my $res = false;
	if( !Mods::Toops::errs()){
		my $sender = $gateway->{mailfrom};
		my $mailto = join( ', ', @{$msg->{mailto}} );
		my $subject = $msg->{subject};
		my $message = $msg->{message};

		my $email = Email::MIME->create(
			header_str => [
				From    => $sender,
				To      => $mailto,
				Subject => $subject
			],
			attributes => {
				encoding => 'quoted-printable',
				charset  => 'UTF-8',
			},
			body_str => $message,
		);

		# Authen::SASL accepts mechanism = CRAM-MD5 PLAIN ANONYMOUS
		# it automatically chooses the best suited for the server
		# which may be forced with 'authent' JSON key
		my $opts = {};
		#$opts->{callback} = { user => $gateway->{username}, pass => $gateway->{password} } if $gateway->{username};
		#$opts->{mechanism} = $gateway->{authent} if $gateway->{authent};
		#my $sasl = Authen::SASL->new( %{$opts} );
		#print Dumper( $sasl );

		# Email::Sender::Transport::SMTP is able to choose a default port if we set the 'ssl' option to 'ssl' or true
		# but is not able to set a default ssl option starting from the port - fix that here
		$opts = {};
		$opts->{host} = $gateway->{host} || 'localhost';
		$opts->{port} = $gateway->{port} if $gateway->{port};
		#$opts->{sasl_authenticator} = $sasl;
		$opts->{sasl_username} = $gateway->{username} if $gateway->{username};
		$opts->{sasl_password} = $gateway->{password} if $gateway->{username};
		$opts->{helo} = $gateway->{helo} || uc hostname.".localdomain";
		$opts->{ssl} = $gateway->{security} if $gateway->{security};
		if( $gateway->{port} && !$gateway->{security} ){
			$opts->{ssl} = 'ssl' if $gateway->{port} == 465;
			$opts->{ssl} = 'starttls' if $gateway->{port} == 587;
		}
		$opts->{timeout} = $gateway->{timeout} || 60;
		$opts->{debug} = false;
		$opts->{debug} = $gateway->{debug} if exists $gateway->{debug};
		$opts->{ssl_options} = { SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE };
		my $transport = Email::Sender::Transport::SMTP->new( $opts );
		#print Dumper( $transport );

		# catching IO::Handle timeout doesn't work here - it abends with 'Bad file descriptor' error message
		try {
			my $res = sendmail( $email, { transport => $transport });
		} catch {
			Mods::Message::msgWarn( "sendmail() $!" );
			print Dumper( $res );
		};
	}
	return $res;
}

1;
