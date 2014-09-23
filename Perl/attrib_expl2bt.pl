=head1 NAME

attrib_expl2bt.pl - This script will add attributen from exploitatie dossier to bedrijfstoepassingen.

=head1 VERSION HISTORY

version 1.0 17 September 2014 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will check on 'bedrijfstoepassingsnummers' that are in exploitatie dossier but that are not in 'bedrijfsapplicatie'. These items will be listed with a warning.

Then the script will add the atttributen to the table 'bedrijfsapplicatie'.

=head1 SYNOPSIS

 attrib_expl2bt.pl

 attrib_expl2bt -h	Usage
 attrib_expl2bt -h 1  Usage and description of the options
 attrib_expl2bt -h 2  All documentation

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

# Find applications in exploitatie dossier not in bedrijfsapplicatie.
my $query =  "SELECT apps_exploitatiedossier.bt_nummer as bt_nummer, [consolidatie bedrijfstoepassingen].naam as naam, 
					 [consolidatie bedrijfstoepassingen].[eigenaar beleidsdomein] as b_eig, 
					 [consolidatie bedrijfstoepassingen].[eigenaar entiteit] as e_eig 
			  FROM apps_exploitatiedossier
		      LEFT JOIN [consolidatie bedrijfstoepassingen] ON apps_exploitatiedossier.bt_nummer = [consolidatie bedrijfstoepassingen].[bt_nummer] 
			  WHERE apps_exploitatiedossier.bt_nummer NOT IN
			      (SELECT [Nummer bedrijfstoepassing] FROM Bedrijfsapplicatie)";
my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	my $bt_nummer = $$arrayhdl{bt_nummer};
	my $naam = $$arrayhdl{naam} || "geen naam";
	my $b_eig = $$arrayhdl{b_eig} || "";
	my $e_eig = $$arrayhdl{e_eig} || "";
	print "Toepassing $bt_nummer ($naam, $b_eig, $e_eig) niet in tabel bedrijfsapplicatie\n";
}

# Query to update attributen in tabel bedrijfsapplicatie
$query = "UPDATE bedrijfsapplicatie, apps_exploitatiedossier
		  SET bedrijfsapplicatie.BereikbaarheidInternet = apps_exploitatiedossier.BereikbaarheidInternet,
              bedrijfsapplicatie.BereikbaarheidInternetVPN = apps_exploitatiedossier.BereikbaarheidInternetVPN,
              bedrijfsapplicatie.BereikbaarheidVoNet = apps_exploitatiedossier.BereikbaarheidVoNet,
              bedrijfsapplicatie.webservices = apps_exploitatiedossier.webservices,
              bedrijfsapplicatie.sftp = apps_exploitatiedossier.sftp,
              bedrijfsapplicatie.http = apps_exploitatiedossier.http,
              bedrijfsapplicatie.https = apps_exploitatiedossier.https,
              bedrijfsapplicatie.acm_idm = apps_exploitatiedossier.acm_idm,
              bedrijfsapplicatie.ad_ldap = apps_exploitatiedossier.ad_ldap,
              bedrijfsapplicatie.opslagtype = apps_exploitatiedossier.opslagtype,
              bedrijfsapplicatie.reverse_proxy = apps_exploitatiedossier.reverse_proxy
		  WHERE bedrijfsapplicatie.[Nummer bedrijfstoepassing] = apps_exploitatiedossier.bt_nummer";
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
