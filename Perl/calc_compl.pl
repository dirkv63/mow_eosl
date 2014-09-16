=head1 NAME

calc_compl.pl - This script calculates completeness of a table.

=head1 VERSION HISTORY

version 1.0 28 August 2014 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script will calculate completeness of tables listed in ini file. A cell is complete if it has anything else than a NULL value.

=head1 SYNOPSIS

 calc_compl.pl

 calc_compl -h	Usage
 calc_compl -h 1  Usage and description of the options
 calc_compl -h 2  All documentation

=head1 OPTIONS

=over 4

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh, @tables);

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
use DbUtil qw(db_connect do_select_arrays);

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

sub calc_content($$) {
	my ($content_ref, $tablename) = @_;
	my $cells_per_row = 0;
	my $row_cnt = 0;
	my $cell_cnt = 0;
	my $cell_defined = 0;
	# Work on the rows
	foreach my $row (@$content_ref) {
		$row_cnt++;
		# Work on the cells
		foreach my $cell (@$row) {
			$cell_cnt++;
			if (defined $cell) {
				$cell_defined++;
			}
		}
	}
	if ($row_cnt > 0) {
		$cells_per_row = $cell_cnt / $row_cnt;
	}
	print "$tablename;$row_cnt;$cells_per_row;$cell_cnt;$cell_defined\n";
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

# Initialize List of Tables
@tables = $cfg->val("Completeness", "table");

# Make database connection for vo database
$dbh = db_connect("mow_eosl") or exit_application(1);
$dbh->{LongTruncOk} = 1;

foreach my $table (@tables) {
	my $query =  "SELECT * FROM $table";
	my $table_ref = do_select_arrays($dbh, $query);
	if ((defined $table_ref) && (@$table_ref > 0)) {
		calc_content($table_ref, $table);
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
