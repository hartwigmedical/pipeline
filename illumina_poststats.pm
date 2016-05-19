#!/usr/bin/perl -w

#######################################################
### illumina_poststats.pm
### - Create post mapping statistics using bammetrics
###
### Authors: R.F.Ernst, S.W.Boymans, H.H.D.Kerstens
###
#######################################################

package illumina_poststats;

use strict;
use POSIX qw(tmpnam);
use FindBin;
use illumina_sge;
use illumina_template;


sub runPostStats {
    ###
    # Run post mapping statistics tools with settings from config/ini file.
    ###
    my $configuration = shift;
    my %opt = %{$configuration};
    my @runningJobs; #internal job array
    my $runName = (split("/", $opt{OUTPUT_DIR}))[-1];
    my $jobID = "PostStats_".get_job_id();
    my $jobIDCheck = "PostStats_Check_".get_job_id();

    if(! -e "$opt{OUTPUT_DIR}/logs/PostStats.done"){
	## Setup Bammetrics
	my $command = "perl $opt{BAMMETRICS_PATH}/bamMetrics.pl ";
	foreach my $sample (@{$opt{SAMPLES}}){
	    my $sampleBam = "$opt{OUTPUT_DIR}/$sample/mapping/$opt{BAM_FILES}->{$sample}";
	    $command .= "-bam $sampleBam ";
	    if (@{$opt{RUNNING_JOBS}->{$sample}}) {
		push(@runningJobs, join(",",@{$opt{RUNNING_JOBS}->{$sample}}));
	    }
	}
	$command .= "-output_dir $opt{OUTPUT_DIR}/QCStats/ ";
	$command .= "-run_name $runName ";
	$command .= "-genome $opt{GENOME} ";
	$command .= "-queue $opt{POSTSTATS_QUEUE} ";
	$command .= "-queue_threads $opt{POSTSTATS_THREADS} ";
	$command .= "-queue_mem $opt{POSTSTATS_MEM} ";
	$command .= "-queue_time $opt{POSTSTATS_TIME} ";
	$command .= "-queue_project $opt{CLUSTER_PROJECT} ";
	$command .= "-picard_path $opt{PICARD_PATH} ";
	$command .= "-debug ";

	if ( ($opt{POSTSTATS_TARGETS}) && ($opt{POSTSTATS_BAITS}) ) {
	    $command .= "-capture ";
	    $command .= "-targets $opt{POSTSTATS_TARGETS} ";
	    $command .= "-baits $opt{POSTSTATS_BAITS} ";
	} else {
	    $command .= "-wgs ";
	    $command .= "-coverage_cap 250 ";
	}

	if ( $opt{SINGLE_END} ) {
	    $command .= "-single_end ";
	}

	if ( $opt{CLUSTER_RESERVATION} eq "yes") {
	    $command .= "-queue_reserve ";
	}

	my $bashFile = $opt{OUTPUT_DIR}."/jobs/".$jobID.".sh";
	my $logDir = $opt{OUTPUT_DIR}."/logs";

	from_template("PostStats.sh.tt", $bashFile, command => $command, runName => $runName, jobID => $jobID, jobIDCheck => $jobIDCheck,  opt => \%opt);

	my $qsub = &qsubTemplate(\%opt,"POSTSTATS");
	if (@runningJobs){
	    system $qsub." -o ".$logDir."/PostStats_".$runName.".out -e ".$logDir."/PostStats_".$runName.".err -N ".$jobID." -hold_jid ".
		join(",",@runningJobs)." ".$bashFile;
	} else {
	    system $qsub." -o ".$logDir."/PostStats_".$runName.".out -e ".$logDir."/PostStats_".$runName.".err -N ".$jobID." ".$bashFile;
	}

	### Check Poststats result
	my $bashFileCheck = $opt{OUTPUT_DIR}."/jobs/".$jobIDCheck.".sh";
	from_template("PostStats_Check.sh.tt", $bashFileCheck, runName => $runName, opt => \%opt);

	system $qsub." -o ".$logDir."/PostStats_".$runName.".out -e ".$logDir."/PostStats_".$runName.".err -N ".$jobIDCheck.
	    " -hold_jid bamMetrics_report_".$runName.",".$jobID." ".$bashFileCheck;
	return $jobIDCheck;

    } else {
	print "WARNING: $opt{OUTPUT_DIR}/logs/PostStats.done exists, skipping\n";
    }
}

############
sub get_job_id {
   my $id = tmpnam();
      $id=~s/\/tmp\/file//;
   return $id;
}

sub bashAndSubmit {
    my $command = shift;
    my $sample = shift;
    my %opt = %{shift()};

    my $jobID = "PostStats_".$sample."_".get_job_id();
    my $bashFile = $opt{OUTPUT_DIR}."/".$sample."/jobs/PICARD_".$sample."_".$jobID.".sh";
    my $logDir = $opt{OUTPUT_DIR}."/".$sample."/logs";

    open OUT, ">$bashFile" or die "cannot open file $bashFile\n";
    print OUT "#!/bin/bash\n\n";
    print OUT "cd $opt{OUTPUT_DIR}\n";
    print OUT "$command\n";
    my $qsub = &qsubTemplate(\%opt,"POSTSTATS");
    if ( @{$opt{RUNNING_JOBS}->{$sample}} ){
	system $qsub." -o ".$logDir."/PostStats_".$sample."_".$jobID.".out -e ".$logDir."/PostStats_".$sample."_".$jobID.".err -N ".$jobID.
	    " -hold_jid ".join(",",@{$opt{RUNNING_JOBS}->{$sample} })." ".$bashFile;
    } else {
	system $qsub." -o ".$logDir."/PostStats_".$sample."_".$jobID.".out -e ".$logDir."/PostStats_".$sample."_".$jobID.".err -N ".$jobID.
	    " ".$bashFile;
    }
    return $jobID;
}

############

1;
