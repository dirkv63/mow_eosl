=head1 NAME

get_cons_relaties.pl - This script will populate the consolidated relations table.

=head1 VERSION HISTORY

version 1.0 19 September 2014 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will get the configuration for the specified CI. The CI number is the 'toepassingsomgeving'. Find the bedrijfstoepassing. 
Walk down the configuration and collect all applicatiecomponent - applicatiecomponentinstallatie - computersysteem triplets. Add them to the table. Klaar is Kees. 

=head1 SYNOPSIS

 get_cons_relaties.pl

 get_cons_relaties -h	Usage
 get_cons_relaties -h 1  Usage and description of the options
 get_cons_relaties -h 2  All documentation

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

sub handle_relation($$$$) {
	my($id_source, $id_target, $type_source, $type_target) = @_;
	if (($type_source eq "bedrijfsapplicatieomgeving") &&
		($type_target eq "applicatiecomponent")) {
		# xBedrijfsapplOmg2ApplComp - OK
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "applicatiecomponent")) {
		# xApplComp2ApplComp - OK
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "applicatiecompinstall")) {
		# xApplComp2ApplCompInstall - OK
	} elsif (($type_source eq "applicatiecompinstall") &&
		($type_target eq "computersystem")) {
		# xApplCompInstall2ComputerSystem - OK
	} elsif (($type_source eq "computersystem") &&
		($type_target eq "computersystem")) {
		# xComputerSystemOnComputerSystem - OK
	} elsif (($type_source eq "applicatiecompinstall") &&
		($type_target eq "applicatiecompinstall")) {
		# xApplCompInst2ApplCompInst - OK
	} elsif (($type_source eq "applicatiecomponent") &&
		($type_target eq "computersystem")) {
		print "Unexpected relation $type_source to $type_target\n";
	} else {
		$log->error("Unexpected Relation from $type_source to $type_target");
		exit_application(1);
	}
}


sub go_down($$$$$$$$$);

sub go_down($$$$$$$$$) {
	my ($cmdb_id, $name, $type, $id, $ba_id, $bao_id, $ac_id, $aci_id, $cs_id) = @_;
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
		if ($relation eq "maakt gebruik van") { next; }
		handle_relation($id, $id_target, $type, $type_target);
		# Add Component to one of the tables.
		if ($type_target eq "applicatiecomponent") {
			$ac_id = $cmdb_id_target;
		} elsif ($type_target eq "applicatiecompinstall") {
			$aci_id = $cmdb_id_target;
		} elsif ($type_target eq "computersystem") {
			$cs_id = $cmdb_id_target;
			my @fields = qw(bedrijfsapplicatie_id bedrijfsapplicatieomgeving_id
			                applicatiecomponent_id applicatiecomponentinstallatie_id
							computersysteem_id);
			my @vals = ($ba_id, $bao_id, $ac_id, $aci_id, $cs_id);
			create_record($dbh, "yconfiguratie", \@fields, \@vals);
		}
		# Conditions to stop go down again
		if ((defined $not_below_fys) && ($ci_type_target eq "FYSIEKE COMPUTER")) { next; }
		# No more conditions, so continue to go down
		go_down($cmdb_id_target, $naam_target, $type_target, $id_target, $ba_id, $bao_id, $ac_id, $aci_id, $cs_id);
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
my @tables = qw (yconfiguratie);
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
my $query =  "SELECT bao.id, bao.naam, bao.cmdb_id as bao_cmdb_id, ba.[cmdb id] as ba_cmdb_id 
			  FROM Bedrijfsapplicatieomgeving bao
			  INNER JOIN bedrijfsapplicatie ba ON ba.id = bao.BedrijfsapplicatieID";

my $ref = do_select($dbh, $query);
foreach my $arrayhdl (@$ref) {
	my ($ac_id, $aci_id, $cs_id);
	my $naam = $$arrayhdl{naam};
	my $cmdb_id = $$arrayhdl{bao_cmdb_id};
	my $type = "bedrijfsapplicatieomgeving";
	my $ba_id = $$arrayhdl{ba_cmdb_id};
	my $bao_id = $cmdb_id;
	my $id = $$arrayhdl{id};
	$stepcnt = 0;
	print "Working on $naam ($cmdb_id)\n";
	go_down($cmdb_id, $naam, $type, $id, $ba_id, $bao_id, $ac_id, $aci_id, $cs_id);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Check for CMDB ID 60833. Double 'maakt gebruik van' relation??

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
