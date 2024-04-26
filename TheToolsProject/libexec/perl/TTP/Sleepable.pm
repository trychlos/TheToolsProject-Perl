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
#
# Let several tasks have different sleep intervals.
#
# First declare all your tasks:
#   sleepableDeclareFn( sub, interval )
#
# Do not omit to declare a stop function:
# It will be called every second to see if the loop may continue.
#   sleepableDeclareStop( sub )
#   The stop() function is called with this object as a single parameter.
#   Must return a truethy value to stop the infinite loop.
#
# Then sleepableStart(), and let each sub be called at its own interval

package TTP::Sleepable;
our $VERSION = '1.00';

use strict;
use warnings;

use Data::Dumper;
use Time::Hires qw( time usleep );

use TTP::Constants qw( :all );
use TTP::Message qw( :all );

my $Const = {
};

### Private methods

# -------------------------------------------------------------------------------------------------
# See if a function has reached its requested interval
# (I):
# - last run, may be undef or zero
# - requested interval (ms)
# (O):
# - true if the function should be called, false else

sub _isCallable {
	my ( $self, $last, $interval ) = @_;

	my $callable = false;
	if( $last ){
		my $now = time();
		$callable = ( $now - $last > 1000*$interval );
	} else {
		$callable = true;
	}

	return $callable;
}

### Public methods
### https://metacpan.org/pod/Role::Tiny
### All subs created after importing Role::Tiny will be considered methods to be composed.
use Role::Tiny;

requires qw( _newBase );

# -------------------------------------------------------------------------------------------------
# Declare a new function to be called on its own interval
# (I):
# - the code reference
# - the parms to pass to the code ref as a single scalar (most probably a hash or an array ref ?)
# - the interval call in ms.
# (O):
# - true unless an error has occurred

sub sleepableDeclareFn {
	my ( $self, $sub, $parms, $interval ) = @_;

	my $success = false;
	my $ref = ref( $sub );
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects a code reference, found '$ref'" ) if $ref ne 'CODE';

	$ref = ref( $interval );
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects an interval integer, found '$ref'" ) if $ref;
	msgErr( __PACKAGE__."::sleepableDeclareFn() expects a positive interval, found '$interval'" ) if !$interval || $interval <= 0;

	if( !TTP::errs()){
		push( @{$self->{_sleepable}{fn}}, { sub => $sub, parms => $parms, interval => $interval } );
		$success = true;
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Declare a function to be called for stop
# (I):
# - the code reference
# (O):
# - true unless an error has occurred

sub sleepableDeclareStop {
	my ( $self, $sub ) = @_;

	my $success = false;
	my $ref = ref( $sub );
	msgErr( __PACKAGE__."::sleepableDeclareStop() expects a code reference, found '$ref'" ) if $ref ne 'CODE';

	if( !TTP::errs()){
		$self->{_sleepable}{stop} = { sub => $sub };
		$success = true;
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Start an infinite loop which will successively call each declared function at the requested interval.
# This only returns when the stop() function has answered 'true'
# (I):
# - nothing
# (O):
# - true unless an error has occurred

sub sleepableStart {
	my ( $self ) = @_;

	my $success = false;
	msgErr( __PACKAGE__."::sleepableStart() no stop() function has been declared" ) if !defined $self->{_sleepable}{stop};

	if( !TTP::errs()){
		# compute the minimal interval and loop on 1/10e of it
		my $min = 0;
		foreach my $it ( @{$self->{_sleepable}{fn}} ){
			my $interval = $it->{interval};
			$min = $interval if !$min || $min > $interval;
		}
		if( $min <= 0 ){
			msgErr( __PACKAGE__."::sleepableStart() cowardly refuse to start the infinite loop with a non-positive interval, found '$min'" );
		} else {
			# the sleep time in ms
			my $loop = $min / 10.0;
			# the sleep time is usec
			my $uloop = 1000.0 * $loop;

			# get seconds and microseconds since the epoch
			#my ( $s, $usec ) = gettimeofday();

			my $stop = false;
	
			while( !$stop ){
				# call each function first
				foreach my $it ( @{$self->{_sleepable}{fn}} ){
					if( $self->_isCallable( $it->{last}, $it->{interval} )){
						$it->{sub}->( $self, $it->{params} );
						$it->{last} = time();
					}
				}
				# test for stop
				if( $self->_isCallable( $self->{_sleepable}{stop}{last}, 1000 )){
					$stop = $self->{_sleepable}{stop}{sub}->( $self );
					$self->{_sleepable}{stop}{last} = time();
				}
				usleep( $uloop );
			}

			$success = true;
		}
	}

	return $success;
}

# -------------------------------------------------------------------------------------------------
# Sleepable initialization
# (I):
# - none
# (O):
# -none

after _newBase => sub {
	my ( $self ) = @_;

	$self->{_sleepable} //= {};
	$self->{_sleepable}{fn} = [];
	$self->{_sleepable}{stop} = undef;
};

1;

__END__
