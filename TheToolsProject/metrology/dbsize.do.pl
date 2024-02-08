# @(#) publish all databases size on defined instances
#
# @(-) --[no]help              print this message, and exit [${help}]
# @(-) --[no]verbose           run verbosely [${verbose}]
# @(-) --[no]colored           color the output depending of the message level [${colored}]
# @(-) --[no]dummy             dummy run (ignored here) [${dummy}]
# @(-) --limit=<limit>         limit the published messages [${limit}]
#
# @(@) When limiting the published messages, be conscious that each database provides 7 messages.
#
# Copyright (@) 2023-2024 PWI Consulting

use Data::Dumper;

use Mods::Dbms;
use Mods::Metrology;

my $TTPVars = Mods::Toops::TTPVars();

my $defaults = {
	help => 'no',
	verbose => 'no',
	colored => 'no',
	dummy => 'no',
	limit => -1
};

my $opt_limit = $defaults->{limit};

# note that the sp_spaceused stored procedure returns:
# - TWO resuts sets
# - and that units are in the data: we move them to the column names
# below a sample of the got result
=pod
Changed database context to 'Canal33'.
database_name                                                                                                                    database_size      unallocated space 
-------------------------------------------------------------------------------------------------------------------------------- ------------------ ------------------
Canal33                                                                                                                          18746.06 MB        0.67 MB           
reserved           data               index_size         unused            
------------------ ------------------ ------------------ ------------------
19191824 KB        12965152 KB        6182104 KB         44568 KB          
=cut

# -------------------------------------------------------------------------------------------------
# modify the result set to move the units to the column names
sub _modifySet {
	my ( $set ) = @_;
	my @res = ();
	foreach my $row ( @{$set} ){
		my $it = {};
		foreach my $key ( keys %{$row} ){
			# unchanged keys
			if( $key eq "database_name" ){
				$it->{$key} = $row->{$key};
			} else {
				my $data = $row->{$key};
				my @words = split( /\s+/, $data );
				$it->{$key.'_'.$words[1]} = $words[0];
			}
		}
		push( @res, $it );
	}
	return \@res;
}

# -------------------------------------------------------------------------------------------------
# publish all databases sizes for all defined instances on this host
sub doDbSize {
	my $hostConfig = Mods::Toops::getHostConfig();
	Mods::Toops::msgOut( "publishing databases size on $hostConfig->{name}..." );
	my $count = 0;
	my $instances = Mods::Toops::ttpFilter( `services.pl list -dbms` );
	if( scalar @{$instances} ){
		foreach my $instance ( @{$instances} ){
			last if $count >= $opt_limit && $opt_limit >= 0;
			Mods::Dbms::checkInstanceOpt( $instance );
			my $databases = Mods::Toops::ttpFilter( `dbms.pl list -instance $instance -listdb` );
			foreach my $db ( @{$databases} ){
				last if $count >= $opt_limit && $opt_limit >= 0;
				# sp_spaceused provides two results sets, where each one only contains one data row
				my $sql = "use $db; exec sp_spaceused";
				my $out = Mods::Toops::ttpFilter( `dbms.pl sql -instance $instance -command \"$sql\"` );
				my @resultSet = ();
				foreach my $line ( @{$out} ){
					# skip the first line 'Changed database context to ...' due to the 'use <database>'
					next if $line =~ /Changed database context/;
					#print $line.EOL;
					push( @resultSet, $line );
					if( scalar @resultSet == 3 ){
						my $set = Mods::Metrology::interpretResultSet( @resultSet );
						$set = _modifySet( $set );
						$count += Mods::Metrology::publish( "dbms/$instance/database/$db/dbsize", $set, { maxCount => $opt_limit-$count });
						@resultSet = ();
					}
				}
			}
		}
	} else {
		Mods::Toops::msgOut( "no DBMS instance defined on $host" );
	}
	Mods::Toops::msgOut( "$count published message(s)" );
}

# =================================================================================================
# MAIN
# =================================================================================================

if( !GetOptions(
	"help!"				=> \$TTPVars->{run}{help},
	"verbose!"			=> \$TTPVars->{run}{verbose},
	"colored!"			=> \$TTPVars->{run}{colored},
	"dummy!"			=> \$TTPVars->{run}{dummy},
	"limit=i"			=> \$opt_limit )){

		Mods::Toops::msgOut( "try '$TTPVars->{command_basename} $TTPVars->{verb} --help' to get full usage syntax" );
		Mods::Toops::ttpExit( 1 );
}

if( Mods::Toops::wantsHelp()){
	Mods::Toops::helpVerb( $defaults );
	Mods::Toops::ttpExit();
}

Mods::Toops::msgVerbose( "found verbose='".( $TTPVars->{run}{verbose} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found colored='".( $TTPVars->{run}{colored} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found dummy='".( $TTPVars->{run}{dummy} ? 'true':'false' )."'" );
Mods::Toops::msgVerbose( "found limit='$opt_limit'" );

if( !Mods::Toops::errs()){
	doDbSize();
}

Mods::Toops::ttpExit();
