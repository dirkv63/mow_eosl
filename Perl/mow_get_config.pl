=head1 NAME

mow_get_config.pl - This script will get the configuration for the Toepassingsomgeving CI, for MOW move.

=head1 VERSION HISTORY

version 1.0 19 August 2014 DV

=over 4

=item *

Initial release, based on get_config.pl from eIB project.

=back

=head1 DESCRIPTION

This script will get the configuration for the specified CI. The CI number is input parameter. The CI will be a 'Toepassingsomgeving', and we need to understand the 'path down', so not up to the 'Bedrijfstoepassing'. Walk down until Physical Server level, store all relevant information in table 'ApplicatieComponent', 'ApplicatieComponentInstall' or 'ComputerSystem'. Remember to store 'ApplicatieComponentType' and Technology Library. 

=head1 SYNOPSIS

 mow_get_config.pl

 mow_get_config -h	Usage
 mow_get_config -h 1  Usage and description of the options
 mow_get_config -h 2  All documentation

=head1 OPTIONS

=over 4

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($log, $dbh, $cmdb_id, $stepcnt, %ci_hash, $get_eosl, %appl_comp_type, %techlib, %locaties);
my (@ignore_types, @applicatiecomponenten, @applicatiecompinstalls, @computersystems);
my $no_gebruiksrel = "Yes (don't look at gebruiksrelaties)";
my $not_below_fys = "Yes (don't go beyond Physical Computers";
my $max_steps = 100;

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

=pod

=head2 Get Comp Type

This procedure will get a Component Type and translates this to the corresponding Table Name.

=cut

sub get_comp_type($) {
	my ($ci_type) = @_;
	my $comp_type;
	if (grep {lc($_) eq lc($ci_type)} @applicatiecomponenten) {
		$comp_type = "applicatiecomponent";
	} elsif (grep {lc($_) eq lc($ci_type)} @applicatiecompinstalls) {
		$comp_type = "applicatiecompinstall";
	} elsif (grep {lc($_) eq lc($ci_type)} @computersystems) {
		$comp_type = "computersystem";
	} elsif (grep {lc($_) eq lc($ci_type)} @ignore_types) {
		$comp_type = "ignore";
	} else {
		my $msg = "Unexpected Component Type $ci_type";
		$log->error($msg);
		exit_application(1);
	}
	return $comp_type;
}

=pod

=head2 Get Appl Comp Type

This procedure will get the Component Type/Categorie for the component and links it with the Application Component Type table.

=cut

sub get_applcomptypeid($$) {
	my ($type, $categorie) = @_;
	my $key = $type . "|" . $categorie;
	if (exists $appl_comp_type{$key}) {
		return $appl_comp_type{$key};
	}
	my @fields = qw(type categorie);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "applicatiecomponenttype", \@fields, \@vals);
	# Get ID for the inserted record
	my $query = "SELECT id 
				 FROM applicatiecomponenttype
				 WHERE type = ?
				 AND categorie = ?";
	my $ref = singleton_select($dbh, $query, ($type, $categorie));
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in applicatiecomponenttype");
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $id = $$arrayhdl{id};
    $appl_comp_type{$key} = $id;
    return $id;
}

sub get_locatie($) {
	my ($naam) = @_;
	if ($naam eq "geen locatie") {
		return 0;
	}
	if (exists $locaties{$naam}) {
		return $locaties{$naam};
	}
	my @fields = qw(naam);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "cv_locatie", \@fields, \@vals);
	# Get ID for the inserted record
	my $query = "SELECT id 
				 FROM cv_locatie
				 WHERE naam = ?";
	my $ref = singleton_select($dbh, $query, @vals);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in locaties");
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $id = $$arrayhdl{id};
    $locaties{$naam} = $id;
    return $id;
}

=pod

=head2 Techlib

This procedure will get the Product and Producent and stores it in the TechnologieBibliotheek.

=cut

sub handle_techlib($$$$$) {
	my ($producent, $product, $versie, $ComponentID, $ComponentType) = @_;
	my ($TechnologieBibliotheekID);
	my $key = $product . "|" . $producent . "|" . $versie;
	if (length($key) < 2) {
		# No information on product or producent
		return;
	}
	if (exists $techlib{$key}) {
		$TechnologieBibliotheekID = $techlib{$key};
	} else {
		# Add Product / Producent to Techlib to get techlib ID
		my @fields = qw(product producent versie);
		my (@vals) = map { eval ("\$" . $_ ) } @fields;
		create_record($dbh, "TechnologieBibliotheek", \@fields, \@vals);
		# Get ID for the inserted record
		my $query = "SELECT id 
					 FROM TechnologieBibliotheek
					 WHERE product = ?
					 AND producent = ?
					 AND versie = ?";
		my $ref = singleton_select($dbh, $query, @vals);
		unless ((defined $ref) && (1 == @$ref)) {
			$log->error("($product, $producent) expected but not found in TechnologieBibliotheek");
			exit_application(1);
		}
		my $arrayhdl = $ref->[0];
		$TechnologieBibliotheekID = $$arrayhdl{id};
	    $techlib{$key} = $TechnologieBibliotheekID;
	}
	# Add Relation to xApplCompTechnbib
	my @fields = qw(ComponentID TechnologieBibliotheekID ComponentType);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "xApplcompTechnbib", \@fields, \@vals);
}

=pod

=head2 Application Component

An Application Component is found and handled here.

=cut

sub handle_applcomp($$) {
	my ($cmdb_id, $naam) = @_;
	# This component is not yet in the table, add it.
	my $query = "SELECT ci_type, ci_categorie, product, producent
				 FROM componenten
				 WHERE cmdb_id = $cmdb_id";
	my $ref = singleton_select($dbh, $query);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in componenten");
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $ci_type = $$arrayhdl{ci_type} || "";
	my $ci_categorie = $$arrayhdl{ci_categorie} || "";
	my $product = $$arrayhdl{product} || "";
	my $producent = $$arrayhdl{producent} || "";
	my $applicatiecomponenttypeid = get_applcomptypeid($ci_type, $ci_categorie);
	my @fields = qw(applicatiecomponenttypeid cmdb_id naam);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "applicatiecomponent", \@fields, \@vals);
	# Get ID for the inserted record
	$query = "SELECT id 
				 FROM applicatiecomponent
				 WHERE applicatiecomponenttypeid = ?
				 AND cmdb_id = ?
				 AND naam = ?";
	$ref = singleton_select($dbh, $query, @vals);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in applicatiecomponenttype");
		exit_application(1);
	}
	$arrayhdl = $ref->[0];
	my $id = $$arrayhdl{id};
	# On Application Component Level, product information is about
	# the configured product, not on versions or release numbers.
	# Ignore Techlib information
	# handle_techlib($producent, $product, $versie, $id, "applicatiecomponent");
    return $id;
}

=pod

=head2 Application Component Install

An Application Component Install is found and handled here.

=cut

sub handle_applcompinstall($$) {
	my ($cmdb_id, $naam) = @_;
	# This component is not yet in the table, add it.
	my $query = "SELECT ci_type, ci_categorie, product, producent, versie
				 FROM componenten
				 WHERE cmdb_id = $cmdb_id";
	my $ref = singleton_select($dbh, $query);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in componenten");
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $ci_type = $$arrayhdl{ci_type} || "";
	my $ci_categorie = $$arrayhdl{ci_categorie} || "";
	my $product = $$arrayhdl{product} || "";
	my $producent = $$arrayhdl{producent} || "";
	my $versie = $$arrayhdl{versie} || "";
	my $applicatiecomponenttypeid = get_applcomptypeid($ci_type, $ci_categorie);
	my @fields = qw(applicatiecomponenttypeid cmdb_id naam);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "applicatiecomponentinstall", \@fields, \@vals);
	# Get ID for the inserted record
	$query = "SELECT id 
				 FROM applicatiecomponentinstall
				 WHERE applicatiecomponenttypeid = ?
				 AND cmdb_id = ?
				 AND naam = ?";
	$ref = singleton_select($dbh, $query, @vals);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in applicatiecompinstall");
		exit_application(1);
	}
	$arrayhdl = $ref->[0];
	my $id = $$arrayhdl{id};
	handle_techlib($producent, $product, $versie, $id, "applicatiecomponentinstall");
    return $id;
}

sub handle_computersystem($$) {
	my ($cmdb_id, $naam) = @_;
	# This component is not yet in the table, add it.
	my $query = "SELECT ci_type, ci_categorie, os, os_versie, locatie
				 FROM componenten
				 WHERE cmdb_id = $cmdb_id";
	my $ref = singleton_select($dbh, $query);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in componenten");
		exit_application(1);
	}
	my $arrayhdl = $ref->[0];
	my $ci_type = $$arrayhdl{ci_type} || "";
	my $ci_categorie = $$arrayhdl{ci_categorie} || "";
	my $versie = $$arrayhdl{os_versie} || "geen OS versie";
	my $product = $$arrayhdl{os} || "geen OS";
	my $locatie = $$arrayhdl{locatie} || "geen locatie";
	my $LocatieID = get_locatie($locatie);
	my $computertypeid = get_applcomptypeid($ci_type, $ci_categorie);
	my @fields = qw(computertypeid cmdb_id naam LocatieID);
	my (@vals) = map { eval ("\$" . $_ ) } @fields;
	create_record($dbh, "computersystem", \@fields, \@vals);
	# Get ID for the inserted record
	$query = "SELECT id 
				 FROM computersystem
				 WHERE computertypeid = ?
				 AND cmdb_id = ?
				 AND naam = ?
				 AND locatieid = ?";
	$ref = singleton_select($dbh, $query, @vals);
	unless ((defined $ref) && (1 == @$ref)) {
		$log->error("$cmdb_id expected but not found in applicatiecompinstall");
		exit_application(1);
	}
	$arrayhdl = $ref->[0];
	my $id = $$arrayhdl{id};
	my $producent = "";
	handle_techlib($producent, $product, $versie, $id, "computersystem");
    return $id;
}

sub handle_relation($$$$) {
	my($id_source, $id_target, $type_source, $type_target) = @_;
	if (($type_source eq "bedrijfsapplicatieomgeving") &&
		($type_target eq "applicatiecomponent")) {
		# xBedrijfsapplOmg2ApplComp
		my @fields = qw(BedrijfsapplicatieomgevingID ApplicatiecomponentID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xBedrijfsapplOmg2ApplComp", \@fields, \@vals);
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "applicatiecomponent")) {
		# xApplComp2ApplComp
		my @fields = qw(ApplCompSourceID ApplCompTargetID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xApplComp2ApplComp", \@fields, \@vals);
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "applicatiecompinstall")) {
		# xApplComp2ApplCompInstall
		my @fields = qw(ApplCompID ApplCompInstallID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xApplComp2ApplCompInstall", \@fields, \@vals);
	} elsif (($type_source eq "applicatiecompinstall") &&
		($type_target eq "computersystem")) {
		# xApplCompInstall2ComputerSystem
		my @fields = qw(ApplCompInstallID ComputerSysteemID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xApplCompInstall2ComputerSystem", \@fields, \@vals);
	} elsif (($type_source eq "computersystem") &&
		($type_target eq "computersystem")) {
		# xComputerSystemOnComputerSystem
		my @fields = qw(ComputerSystemLeftID ComputerSystemRightID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xComputerSystemOnComputerSystem", \@fields, \@vals);
	} elsif (($type_source eq "applicatiecompinstall") &&
		($type_target eq "applicatiecompinstall")) {
		# xApplCompInst2ApplCompInst
		my @fields = qw(ApplCompInstLeftID ApplCompInstRightID);
		my @vals = ($id_source, $id_target);
		create_record($dbh, "xApplCompInst2ApplCompInst", \@fields, \@vals);
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "computersystem")) {
		print "Unexpected relation $type_source to $type_target\n";
	} else {
		$log->error("Unexpected Relation from $type_source to $type_target");
		exit_application(1);
	}
}


sub go_down($$$$);

sub go_down($$$$) {
	my ($cmdb_id, $name, $type, $id) = @_;
	# Check for loops
	$stepcnt++;
	if ($stepcnt > $max_steps) {
		$log->error("Looks like we are in a loop for $cmdb_id ($stepcnt steps)");
		exit_application(1);
	}
	my $query = "SELECT relation, cmdb_id_target, naam_target, ci_type_target
				 FROM relations
				 WHERE cmdb_id_source = ?
				   AND naam_source    = ?";
	my $ref = do_select($dbh, $query, ($cmdb_id, $name));
	foreach my $arrayhdl (@$ref) {
		my ($id_target);
		my $relation = $$arrayhdl{relation};
		my $cmdb_id_target = $$arrayhdl{cmdb_id_target};
		my $naam_target = $$arrayhdl{naam_target};
		my $ci_type_target = $$arrayhdl{ci_type_target};
		$log->debug("Relation: $relation - $cmdb_id_target - $naam_target - $ci_type_target");
		if ((defined $no_gebruiksrel) && ($relation eq "maakt gebruik van")) {
			# Don't look at 'maakt gebruik van' relation
			next;
		}
		my $type_target = get_comp_type($ci_type_target);
		# Don't investigate further for Jobs
		if ($type_target eq "ignore") { next; } 
		# Check op loops
		my $ci_key = "$cmdb_id_target|$naam_target";
		if (exists $ci_hash{$ci_key}) {
			# Only add relation in this case,
			# but do not go_down anymore.
			if ($ci_hash{$ci_key} < 0) {
				$log->error("$ci_key not in one of the tables");
				next;
			}
			handle_relation($id, $ci_hash{$ci_key}, $type, $type_target);
		} else {
			# Add to hash to avoid loops
			$ci_hash{$ci_key} = -1;
			# Add Component to one of the tables.
			if ($type_target eq "applicatiecomponent") {
				$id_target = handle_applcomp($cmdb_id_target, $naam_target);
			} elsif ($type_target eq "applicatiecompinstall") {
				$id_target = handle_applcompinstall($cmdb_id_target, $naam_target);
			} elsif ($type_target eq "computersystem") {
				$id_target = handle_computersystem($cmdb_id_target, $naam_target);
			}
			# Remember the id for this target.
			$ci_hash{$ci_key} = $id_target;
			handle_relation($id, $id_target, $type, $type_target);
			# Conditions to stop go down again
			if ($relation eq "maakt gebruik van") { next; }
			if ((defined $not_below_fys) && ($ci_type_target eq "FYSIEKE COMPUTER")) { next; }
			# No more conditions, so continue to go down
			go_down($cmdb_id_target, $naam_target, $type_target, $id_target);
		}
	}
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

# Initialize component types
@applicatiecomponenten = $cfg->val("TYPES", "applicatiecomponent");
@applicatiecompinstalls = $cfg->val("TYPES", "applcompinstall");
@computersystems = $cfg->val("TYPES", "computersystem");
@ignore_types = $cfg->val("TYPES", "ignore_type");

# Make database connection for vo database
$dbh = db_connect("mow_eosl") or exit_application(1);

# Delete tables in sequence
print "Start to purge tables\n";
my @tables = qw (applicatiecomponent applicatiecomponenttype applicatiecomponentinstall
				 computersystem cv_locatie TechnologieBibliotheek xApplcompTechnbib
                 xBedrijfsapplOmg2ApplComp xApplComp2ApplComp xApplComp2ApplCompInstall
				 xApplCompInstall2ComputerSystem xComputerSystemOnComputerSystem
				 xApplCompInst2ApplCompInst);
foreach my $table (@tables) {
	if ($dbh->do("delete from $table")) {
		$log->debug("Contents of table $table deleted");
	} else {
		$log->fatal("Failed to delete `$table'. Error: " . $dbh->errstr);
		exit_application(1);
	}
}
print "End purge tables\n";

# First get name for CMDB or Bedrijfstoepassing
my $query =  "SELECT id, naam, cmdb_id FROM Bedrijfsapplicatieomgeving";

my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	my $naam = $$arrayhdl{naam};
	my $cmdb_id = $$arrayhdl{cmdb_id};
	my $type = "bedrijfsapplicatieomgeving";
	my $id = $$arrayhdl{id};
	$stepcnt = 0;
	print "Working on $naam ($cmdb_id)\n";
	go_down($cmdb_id, $naam, $type, $id);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
