#!/usr/bin/perl -w

###################################
### illumina_prestats.pm
### - Run fastqc for each fastq
###
### Author: S.W.Boymans & H.H.D.Kerstens
###################################

package illumina_prestats;

use strict;
use POSIX qw(tmpnam);
use lib "$FindBin::Bin"; #locates pipeline directory
use illumina_sge;
use illumina_template;

sub runPreStats {
    ###
    # Run fastqc
    ###
    my $configuration = shift;
    my %opt = %{$configuration};
    my $jobIds = {};
    
    my $mainJobID = "$opt{OUTPUT_DIR}/jobs/PreStatsMainJob_".get_job_id().".sh";
    print "Creating FASTQC report for the following fastq.gz files:\n";

    my @qsubOut = ();
    foreach my $input (keys %{$opt{FASTQ}}){
	my $coreName = undef;
	$coreName = (split("/", $input))[-1];
	$coreName =~ s/\.fastq.gz//;
	my ($sampleName) =  split("_", $coreName);
	print "\t$input\n"; #print fastq filename

	if(! -e "$opt{OUTPUT_DIR}/$sampleName/logs/PreStats_$sampleName.done"){

	    my $preStatsJobId = "PreStat_$coreName\_".get_job_id();
	    my $preStatsFile = "$opt{OUTPUT_DIR}/$sampleName/jobs/$preStatsJobId.sh";
	    push(@{$jobIds->{$sampleName}}, $preStatsJobId);
	    from_template("PreStat.sh.tt", $preStatsFile, sampleName => $sampleName, coreName => $coreName, input => $input, opt => \%opt);
	    my $qsub = &qsubTemplate(\%opt,"PRESTATS");
	    push(@qsubOut, "$qsub -o $opt{OUTPUT_DIR}/$sampleName/logs/PreStat_$coreName.out -e $opt{OUTPUT_DIR}/$sampleName/logs/PreStats_$coreName.err -N $preStatsJobId $opt{OUTPUT_DIR}/$sampleName/jobs/$preStatsJobId.sh");
	} else {
	    print "\t WARNING: FASTQC report for $input already exists, skipping.\n";
	}

    }

    from_template("PreStatsMainJob.sh.tt", $mainJobID, qsubOut => \@qsubOut, opt => \%opt);
    system("sh $mainJobID");
}

############
sub get_job_id {
   my $id = tmpnam(); 
      $id=~s/\/tmp\/file//;
   return $id;
}
############
1;
