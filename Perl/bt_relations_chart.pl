=head1 NAME

bt_relations_chart.pl - This script will get the relations between bedrijfsapplicaties and put them on a picture.

=head1 VERSION HISTORY

version 1.0 17 September 2014 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will read the interface file to understand the relations between the applications and put these in a picture.

=head1 SYNOPSIS

 bt_relations_chart.pl

 bt_relations_chart -h	Usage
 bt_relations_chart -h 1  Usage and description of the options
 bt_relations_chart -h 2  All documentation

=head1 OPTIONS

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh, %comp, @rels);
my $filedir = "c:/temp/";

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
use DbUtil qw(db_connect do_select singleton_select);

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
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
	$options{"h"} = 0;			# display usage.
}
#Print Usage
# if (defined $options{"h"}) {
#     if ($options{"h"} == 0) {
#         pod2usage(-verbose => 0);
#     } elsif ($options{"h"} == 1) {
#         pod2usage(-verbose => 1);
#     } else {
# 		pod2usage(-verbose => 2);
# 	}
# }
# Get ini file configuration
my $ini = { project => "mow_eosl" };
my $cfg = load_ini($ini);
# Start logging
setup_logging;
$log = get_logger();
$log->info("Start application");
# Show input parameters
if ($log->is_trace()) {
	while (my($key, $value) = each %options) {
		$log->trace("$key: $value");
	}
}
# End handle input values

# Make database connection for vo database
$dbh = db_connect("mow_eosl") or exit_application(1);

# First get Bedrijfstoepassingen in scope
my $query = "SELECT btnummer1, cb_1.naam as naam1,
					cb_1.[eigenaar beleidsdomein] as cb1_bel,
					cb_1.[eigenaar entiteit] as cb1_ent,
					btnummer2, cb_2.naam as naam2, 
					cb_2.[eigenaar beleidsdomein] as cb2_bel, 
					cb_2.[eigenaar entiteit] as cb2_ent
			 FROM Interface, 
			      [consolidatie bedrijfstoepassingen] as cb_1,
			      [consolidatie bedrijfstoepassingen] as cb_2
			 WHERE btnummer1 = cb_1.bt_nummer
			   AND btnummer2 = cb_2.bt_nummer
			   AND (NOT(cb_1.[eigenaar beleidsdomein] = 'Duplicate!'))
			   AND (NOT(cb_2.[eigenaar beleidsdomein] = 'Duplicate!'))";
my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	my $btnummer1 = $$arrayhdl{btnummer1};
	my $naam = $$arrayhdl{naam1} || "geen naam";
	my $bel = $$arrayhdl{cb1_bel} || "";
	my $ent = $$arrayhdl{cb1_ent} || "";
	$comp{$btnummer1} = "$naam ($btnummer1) | $bel | $ent";
	my $btnummer2 = $$arrayhdl{btnummer2};
	$naam = $$arrayhdl{naam2} || "geen naam";
	$bel = $$arrayhdl{cb2_bel} || "";
	$ent = $$arrayhdl{cb2_ent} || "";
	$comp{$btnummer2} = "$naam ($btnummer2) | $bel | $ent";
	push @rels, "$btnummer1 -- $btnummer2 [color=black];";
}

# Print information to dot file
my $filename = $filedir . "interface.dot";
my $gifname  = $filedir . "interface.gif";
my $openres = open (DOT, ">$filename");
if (not (defined $openres)) {
	$log->fatal("Could not open $filename for writing, exiting...");
	exit_application(1);
}
print DOT "graph interface {\n";
# Print all components
while (my ($key, $value) = each %comp) {
	print DOT "$key [color=black, shape=record, label=\"{$value}\"];\n";
}
# and print all relations
foreach my $rel (@rels) {
	print DOT "$rel\n";
}
print DOT "}";
close DOT;

my $cmd = "dot -Tgif -Gcharset=latin1 \"$filename\" -o \"$gifname\"";
system($cmd);
exec("\"$gifname\""); 

# exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
