=head1 NAME

get_config.pl - This script will get the configuration for the specified CI

=head1 VERSION HISTORY

version 1.0 04 June 2013 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will get the configuration for the specified CI. The CI number is input parameter. Specify 'normal' CI or number Bedrijfstoepassing.

=head1 SYNOPSIS

 get_config.pl [-c ci_id] [-b bedrijfsnummer] [-g] [-e] [-f]

 get_config -h	Usage
 get_config -h 1  Usage and description of the options
 get_config -h 2  All documentation

=head1 OPTIONS

=over 4

=item B<-c cmdb_id>

The CMDB ID number.

=item B<-b bt_id>

Bedrijfstoepassingnummer. If CMDB_ID is also specified, then bedrijfstoepassingnummer is ignored.

=item B<-g>

If specified, then do not include 'gebruiksrelaties'.

=item B<-e>

If specified, then add EOSL information if available.

=item B<-f>

If specified, then do not go below Fysieke computer.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh, $cmdb_id, $bt_id, %ci_hash, $no_gebruiksrel, $get_eosl, $not_below_fys);
my $filedir = "c:/temp/cv/";

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

sub get_eosl($) {
	my ($cmdb_id) = @_;
	my $query  = "SELECT uitdovend_datum, uitgedoofd_datum
				  FROM componenten
				  WHERE cmdb_id = $cmdb_id";
	my $ref = do_select($dbh, $query);
	my $uitdovend = "";
	my $uitgedoofd = "";
	if (defined $ref) {
		my $record = @$ref[0];
		$uitdovend = $$record{uitdovend_datum} || "";
		$uitgedoofd = $$record{uitgedoofd_datum} || "";
	}
	return ($uitdovend, $uitgedoofd);
}

sub edge_attr($) {
	my ($relation) = @_;
	my $color;
	if (($relation eq "heeft component") || ($relation eq "netwerk connectie")) {
		$color= "blue";
	} elsif ($relation eq "maakt gebruik van") {
		$color = "red";
	} else {
		$color = "black";
	}
	return "[color=$color]";
}

sub get_node_attr($) {
	my ($cmdb_id) = @_;
	my $query = "SELECT * 
				 FROM componenten
				 WHERE cmdb_id = $cmdb_id";
	my $ref = singleton_select($dbh, $query);
	unless ((defined $ref) && (1 == @$ref)) {
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $bt_nummer = $$arrayhdl{BT_NUMMER} || "";
	my $ci_categorie = $$arrayhdl{CI_CATEGORIE} || "";
	my $ci_type = $$arrayhdl{CI_TYPE} || "";
	my $locatie = $$arrayhdl{LOCATIE} || "";
	my $naam = $$arrayhdl{NAAM} || "";
	my $omgeving = $$arrayhdl{OMGEVING} || "";
	my $os = $$arrayhdl{OS} || "";
	my $os_versie = $$arrayhdl{OS_VERSIE} || "";
	my $producent = $$arrayhdl{PRODUCENT} || "";
	my $product = $$arrayhdl{PRODUCT} || "";
	my $status = $$arrayhdl{STATUS} || "";
	my $versie = $$arrayhdl{VERSIE} || "";
	$naam =~ s/[^a-zA-Z0-9 _-]//g;
	my $naam_id = "$naam ($cmdb_id)";
	my @attrib_arr = ($naam_id, $ci_categorie, $ci_type, $locatie, "$os $os_versie", "$producent $product $versie", $status);
	if (defined $get_eosl) {
		my ($uitdovend, $uitgedoofd) = get_eosl($cmdb_id);
		if (length($uitdovend) > 4) {
			push @attrib_arr, "Uitdovend: $uitdovend";
		}
		if (length($uitgedoofd) > 4) {
			push @attrib_arr, "Uitgedoofd: $uitgedoofd";
		}
	}
	# Remove empty values from array
	my (@clean_attribs);
	foreach my $val (@attrib_arr) {
		if (length(trim($val)) > 0) {
			# Replace double quote with single quote
			$val =~ s/\"/\'/g;
			push @clean_attribs, $val;
		}
	}
	return join " | ", @clean_attribs;
}

sub go_down($$);

sub go_down($$) {
	my ($cmdb_id, $name) = @_;
	my $query = "SELECT relation, cmdb_id_target, naam_target, ci_type_target
				 FROM relations
				 WHERE cmdb_id_source = ?
				   AND naam_source    = ?";
	my $ref = do_select($dbh, $query, ($cmdb_id, $name));
	foreach my $arrayhdl (@$ref) {
		my $relation = $$arrayhdl{relation};
		my $cmdb_id_target = $$arrayhdl{cmdb_id_target};
		my $naam_target = $$arrayhdl{naam_target};
		my $ci_type_target = $$arrayhdl{ci_type_target};
		$log->debug("Relation: $relation - $cmdb_id_target - $naam_target - $ci_type_target");
		# Check op loops
		my $edge_attr = edge_attr($relation);
		my $edge_str = "$cmdb_id -> $cmdb_id_target $edge_attr;\n";
		my $ci_key = "$cmdb_id_target|$naam_target";
		if ((defined $no_gebruiksrel) && ($relation eq "maakt gebruik van")) {
			# Don't look at this relation
			next;
		}
		if (exists $ci_hash{$ci_key}) {
			# Only add relation in this case
			print DOT $edge_str;
		} else {
			my $label = "{$naam_target | $cmdb_id_target | $ci_type_target}";
			my $node_attr = get_node_attr($cmdb_id_target);
			print DOT "$cmdb_id_target [shape=record, label=\"{$node_attr}\"];\n";
			print DOT $edge_str;
			$ci_hash{$ci_key} = 1;
			# Conditions to stop go down again
			if ($relation eq "maakt gebruik van") { next; }
			if ((defined $not_below_fys) && ($ci_type_target eq "FYSIEKE COMPUTER")) { next; }
			# No more conditions, so continue to go down
			go_down($cmdb_id_target, $naam_target);
		}
	}
}

sub go_up($$);

sub go_up($$) {
	my ($cmdb_id, $name) = @_;
	my $query = "SELECT relation, cmdb_id_source, naam_source, ci_type_source
				 FROM relations
				 WHERE cmdb_id_target = ?
				   AND naam_target    = ?";
	my $ref = do_select($dbh, $query, ($cmdb_id, $name));
	foreach my $arrayhdl (@$ref) {
		my $relation = $$arrayhdl{relation};
		my $cmdb_id_source = $$arrayhdl{cmdb_id_source};
		my $naam_source = $$arrayhdl{naam_source};
		my $ci_type_source = $$arrayhdl{ci_type_source};
		$log->debug("Relation: $relation - $cmdb_id_source - $naam_source - $ci_type_source");
		# Check op loops
		my $edge_attr = edge_attr($relation);
		my $edge_str = "$cmdb_id_source -> $cmdb_id $edge_attr;\n";
		my $ci_key = "$cmdb_id_source|$naam_source";
		if ((defined $no_gebruiksrel) && ($relation eq "maakt gebruik van")) {
			# Don't look at this relation
			next;
		}
		if (exists $ci_hash{$ci_key}) {
			print DOT $edge_str;
		} else {
			my $edge_attr = edge_attr($relation);
			my $node_attr = get_node_attr($cmdb_id_source);
			my $label = "{$naam_source | $cmdb_id_source | $ci_type_source}";
			print DOT "$cmdb_id_source [shape=record, label=\"{$node_attr}\"];\n";
			print DOT $edge_str;
			$ci_hash{$ci_key} = 1;
			if (not ($relation eq "maakt gebruik van")) {
				go_up($cmdb_id_source, $naam_source);
			}
		}
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("h:c:b:gef", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#	$options{"h"} = 0;			# display usage.
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
$no_gebruiksrel = "Do not show";
$get_eosl = "Show EOSL Information";
$not_below_fys = "Not below Physical Computer";
# Show input parameters
if ($log->is_trace()) {
	while (my($key, $value) = each %options) {
		$log->trace("$key: $value");
	}
}
# End handle input values

# Make database connection for vo database
$dbh = db_connect("mow_eosl") or exit_application(1);

# First get name for CMDB or Bedrijfstoepassing
my $query = "SELECT naam, [cmdb id] as cmdb_id 
			 FROM bedrijfsapplicatie";
my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	my $cmdb_id = $$arrayhdl{cmdb_id};
	my $name = $$arrayhdl{naam};
	my $ci_categorie = "";
	my $ci_type = "";
	my $filename = $filedir . $name . ".dot";
	my $gifname  = $filedir . $name . ".gif";
	my $openres = open (DOT, ">$filename");
	if ((defined $openres)) {
		print "Working on $gifname\n";
	} else {
		$log->fatal("Could not open $filename for writing, exiting...");
		exit_application(1);
	}

	my $node_attr = get_node_attr($cmdb_id);
	print DOT "digraph $cmdb_id {\n";
	print DOT "$cmdb_id [color=red, shape=record, label=\"{$node_attr}\"];\n";

	# Find components from this CI
	go_down($cmdb_id, $name);

	# Find the hierarchy that depends on this CI
	go_up($cmdb_id, $name);

	print DOT "}";

	close DOT;

	my $cmd = "dot -Tgif -Gcharset=latin1 \"$filename\" -o \"$gifname\"";
	system($cmd);
	# exec("\"$gifname\""); 
}

exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
