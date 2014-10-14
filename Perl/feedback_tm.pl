=head1 NAME

feedback_tm.pl - This script consolidates feedback from the toepassingsmanagers.

=head1 VERSION HISTORY

version 1.0 14 October 2014 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script consolidates feedback from the toepassingsmanagers.

=head1 SYNOPSIS

 feedback_tm.pl

 feedback_tm -h	Usage
 feedback_tm -h 1  Usage and description of the options
 feedback_tm -h 2  All documentation

=head1 OPTIONS

=over 4

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh, @updates);

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

# Query to get the attributes
my $query = "SELECT [Nummer bedrijfstoepassing] as bt_nummer,
					[Bereikbaarheid Internet] as bereikbaarheidInternet,
					[Bereikbaarheid InternetVPN] as bereikbaarheidInternetVPN,
					[Bereikbaarheid VoNet] as bereikbaarheidVoNet,
				   	webservices, sftp, http, https,
					acm_idm, ad_ldap, reverse_proxy
			 FROM TM_Feedback";
my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	undef @updates;
	my $bt_nummer = $$arrayhdl{bt_nummer};
	my $bereikbaarheidInternet = $$arrayhdl{bereikbaarheidInternet};
	my $bereikbaarheidInternetVPN = $$arrayhdl{bereikbaarheidInternetVPN};
	my $bereikbaarheidVoNet = $$arrayhdl{bereikbaarheidVoNet};
	my $webservices = $$arrayhdl{webservices};
	my $sftp = $$arrayhdl{sftp};
	my $http = $$arrayhdl{http};
	my $https = $$arrayhdl{https};
	my $acm_idm = $$arrayhdl{acm_idm};
	my $ad_ldap = $$arrayhdl{ad_ldap};
	my $reverse_proxy = $$arrayhdl{reverse_proxy};
	if ($bereikbaarheidInternet ne '?') {
		push @updates, "bereikbaarheidInternet = '$bereikbaarheidInternet'";
	}
	if ($bereikbaarheidInternetVPN ne '?') {
		push @updates, "bereikbaarheidInternetVPN = '$bereikbaarheidInternetVPN'";
	}
	if ($bereikbaarheidVoNet ne '?') {
		push @updates, "bereikbaarheidVoNet = '$bereikbaarheidVoNet'";
	}
	if ($webservices ne '?') {
		push @updates, "webservices = '$webservices'";
	}
	if ($sftp ne '?') {
		push @updates, "sftp = '$sftp'";
	}
	if ($http ne '?') {
		push @updates, "http = '$http'";
	}
	if ($https ne '?') {
		push @updates, "https = '$https'";
	}
	if ($acm_idm ne '?') {
		push @updates, "acm_idm = '$acm_idm'";
	}
	if ($ad_ldap ne '?') {
		push @updates, "ad_ldap = '$ad_ldap'";
	}
	if ($reverse_proxy ne '?') {
		push @updates, "reverse_proxy = '$reverse_proxy'";
	}
	my $cnt = @updates;
	if ($cnt > 0) {
		my $updatestr = join (",", @updates);
		my $query = "UPDATE bedrijfsapplicatie
					 SET $updatestr
					 WHERE bedrijfsapplicatie.[Nummer bedrijfstoepassing] = '$bt_nummer'";
	    if ($dbh->do($query)) {
			$log->info("Bedrijfstoepassing $bt_nummer aangevuld");
		} else {
			$log->fatal("Failed to update table bedrijfsapplicatie ($bt_nummer). " . $dbh->errstr);
		}
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
