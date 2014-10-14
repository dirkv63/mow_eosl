=head1 NAME

cons_attrib.pl - This script will copy the collected attributes to the new table bedrijfsapplicaties.

=head1 VERSION HISTORY

version 1.0 13 October 2014 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will collect attributes from exploitatiedossiers etc and copy them to the new table bedrijfsapplicaties.

=head1 SYNOPSIS

 cons_attrib.pl

 cons_attrib -h	Usage
 cons_attrib -h 1  Usage and description of the options
 cons_attrib -h 2  All documentation

=head1 OPTIONS

=over 4

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh);

#####
# use
#####

use FindBin;
use lib "$FindBin::Bin/lib";

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use DBI();
use DbUtil qw(db_connect do_select singleton_select create_record);

use Log::Log4perl qw(get_logger);
use SimpleLog qw(setup_logging);
use IniUtil qw(load_ini get_ini);

################
# Trace Warnings
################

use Carp;
$SIG{__WARN__} = sub { Carp::confess( @_ ) };

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	$log->info("Exit application with return code $return_code.");
	exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

######
# Main
######

# Handle input values
my %options;
getopts("h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
# 	$options{"h"} = 0;			# display usage.
# }
#Print Usage
if (defined $options{"h"}) {
    if ($options{"h"} == 0) {
        pod2usage(-verbose => 0);
    } elsif ($options{"h"} == 1) {
        pod2usage(-verbose => 1);
    } else {
		pod2usage(-verbose => 2);
	}
}
# Get ini file configuration
my $ini = { project => "mow_eosl" };
my $cfg = load_ini($ini);
# Start logging
setup_logging;
$log = get_logger();
$log->info("Start application");
# End handle input values

# Make database connection for vo database
$dbh = db_connect("mow_eosl") or exit_application(1);

# Query to update attributen in tabel bedrijfsapplicatie
my $query = "UPDATE bedrijfsapplicatie, Bedrijfsapplicatie_Prev
		  SET bedrijfsapplicatie.BereikbaarheidInternet = Bedrijfsapplicatie_Prev.BereikbaarheidInternet,
              bedrijfsapplicatie.BereikbaarheidInternetVPN = Bedrijfsapplicatie_Prev.BereikbaarheidInternetVPN,
              bedrijfsapplicatie.BereikbaarheidVoNet = Bedrijfsapplicatie_Prev.BereikbaarheidVoNet,
              bedrijfsapplicatie.webservices = Bedrijfsapplicatie_Prev.webservices,
              bedrijfsapplicatie.sftp = Bedrijfsapplicatie_Prev.sftp,
              bedrijfsapplicatie.http = Bedrijfsapplicatie_Prev.http,
              bedrijfsapplicatie.https = Bedrijfsapplicatie_Prev.https,
              bedrijfsapplicatie.acm_idm = Bedrijfsapplicatie_Prev.acm_idm,
              bedrijfsapplicatie.ad_ldap = Bedrijfsapplicatie_Prev.ad_ldap,
              bedrijfsapplicatie.opslagtype = Bedrijfsapplicatie_Prev.opslagtype,
              bedrijfsapplicatie.reverse_proxy = Bedrijfsapplicatie_Prev.reverse_proxy
		  WHERE bedrijfsapplicatie.[Nummer bedrijfstoepassing] = Bedrijfsapplicatie_Prev.[Nummer bedrijfstoepassing]";
if ($dbh->do($query)) {
	$log->info("Table bedrijfsapplicatie aangevuld");
} else {
	$log->fatal("Failed to update table bedrijfsapplicatie. " . $dbh->errstr);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
