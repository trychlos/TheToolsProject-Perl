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

use Authen::SASL;
use Data::Dumper;
use Email::MIME;
use Email::Sender::Simple qw( sendmail );
use Email::Sender::Transport::SMTP;
use Net::SMTP;
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
	my $res = false;
	if( !Mods::Toops::errs()){
		my $sender = $gateway->{mailfrom};
		my $mailto = join( ', ', @{$msg->{mailto}} );
		my $subject = $msg->{subject};
		my $message = $msg->{message};
		
		my $mailer = Net::SMTP->new( $gateway->{host}, Port => $gateway->{port}, Debug => 1 );
		Mods::Message::msgErr( "SMTP->new() ".$! ) if !$mailer;
		my $sasl = Authen::SASL->new(
			mechanism => $gateway->{authent},
			callback => { user => $gateway->{username}, pass => $gateway->{password} }
		);
		Mods::Message::msgErr( $! ) if !$sasl;
		my $res = $mailer->auth( $sasl );
		print Dumper( $res );

=pod
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
		my $sasl = Authen::SASL->new(
			mechanism => $gateway->{authent},
			callback => { user => $gateway->{username}, pass => $gateway->{password} }
		);
		print Dumper( $sasl );
		my $transport = Email::Sender::Transport::SMTP->new({
			host => $gateway->{host},
			port => $gateway->{port},
			sasl_authenticator => $sasl,
			helo => uc hostname,
			#ssl => $gateway->{security},
			Debug => 1
		});
		print Dumper( $transport );
		try {
			sendmail( $email, { transport => $transport });
		} catch {
			Mods::Message::msgWarn( $_ );
		};
=cut

=pod
		my $email = MIME::Lite->new(
			From     => $sender,
            To       => $mailto,
            Subject  => $subject,
            Data     => $message
		);
		print "send( \"smtp\", $gateway->{host}, Port => $gateway->{port}, AuthUser => $gateway->{username}, AuthPass => $gateway->{password} )".EOL;
		$res = $email->send( "smtp", , Debug => true, Port => , AuthUser => $gateway->{username}, AuthPass => $gateway->{password} );
		print Dumper( $res );
		$res = true;
=cut
	}
	return $res;
}

1;
