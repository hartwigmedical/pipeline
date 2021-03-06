#!/usr/bin/env perl

use discipline;

use File::Basename;
use File::Find::Rule;
use File::Path qw(make_path);
use File::Spec::Functions;
use File::Temp;
use File::Touch;
use Test::Cmd;
use Test::File;
use Test::Files;
use Test::More;

use lib "t";
# SABR: bug in Test::Prereq 1.x needs filename for test dependencies
require "Util.pm"; ## no critic (Modules::RequireBarewordIncludes)


sub setupTestConfig {
    my ($test, $config_file, $temp_file, $temp_dir) = @_;

    my $genome = catfile("t", "data", "empty.fasta");

    my $config = [];
    ok($test->read($config, $config_file), "read original $config_file") or diag $test->stderr;

    my @fake_file_keys = qw(
        ANNOTATE_DBNSFP_DB
        ANNOTATE_FREQ_DB
        ANNOTATE_COSMIC_DB
        DBSNP_DB
        REALIGNMENT_KNOWN
        BASERECALIBRATION_KNOWN
        MAPPABILITY_BED
        MAPPABILITY_HDR
        HIGH_CONFIDENCE_BED
        HMF_GERMLINE_PON
        HMF_SOMATIC_PON
        HMF_SOMATIC_HOTSPOTS
        BAF_SNPS
        GC_PROFILE
        GRIDSS_BLACKLIST
    );
    my @fake_directory_keys = qw(
        BAMMETRICS_PATH
        BAMUTIL_PATH
        DAMAGE_ESTIMATOR_PATH
        BWA_PATH
        CLUSTER_PATH
        GATK_PATH
        GATK_QUEUE_PATH
        GRIDSS_PATH
        GRIDSS_BWA_PATH
        GRIDSS_PON
        PICARD_PATH
        AMBER_PATH
        COBALT_PATH
        PURPLE_PATH
        CIRCOS_PATH
        SAMBAMBA_PATH
        SNPEFF_PATH
        STRELKA_PATH
        STRELKA_POST_PROCESS_PATH
        TABIX_PATH
        HEALTH_CHECKER_PATH
    );
    my %required_keys = (
        SAMTOOLS_PATH => defined $ENV{SAMTOOLS_PATH} ? $ENV{SAMTOOLS_PATH} : $temp_dir,
        REF_GENOME => $genome,
    );

    foreach my $key (@fake_file_keys) {
        push @{$config}, "$key	$temp_file\n";
    }
    foreach my $key (@fake_directory_keys) {
        push @{$config}, "$key	$temp_dir\n";
    }
    while (my ($key, $value) = each %required_keys) {
        push @{$config}, "$key	$value\n";
    }

    ok($test->write($config_file, @{$config}), "write test-modified $config_file") or diag $test->stderr;
    touch("${genome}.bwt", "${genome}.fai");
    return;
}

sub setupDoneFiles {
    my ($output_dir) = @_;

    my @done_files = map { catfile($output_dir, $_) } (
        # SABR: Add to this when adding new modules
        catfile("logs", "PostStats.done"),
        catfile("logs", "GermlineCalling.done"),
        catfile("logs", "GermlineFiltering.done"),
        catfile("logs", "GermlineAnnotation.done"),
        catfile("logs", "PipelineCheck.done"),
        catfile("logs", "Amber_CPCT12345678R_CPCT12345678T.done"),
        catfile("logs", "Cobalt_CPCT12345678R_CPCT12345678T.done"),
        catfile("logs", "Purple.done"),
        catfile("logs", "HealthCheck.done"),
        catfile("logs", "HealthCheckEvaluation.done"),
        catfile("CPCT12345678R", "logs", "PreStats_CPCT12345678R_HJJLGCCXX_S1_L001_R1_001.fastq.gz.done"),
        catfile("CPCT12345678R", "logs", "PreStats_CPCT12345678R_HJJLGCCXX_S1_L001_R2_001.fastq.gz.done"),
        catfile("CPCT12345678T", "logs", "PreStats_CPCT12345678T_HJJLGCCXX_S1_L001_R1_001.fastq.gz.done"),
        catfile("CPCT12345678T", "logs", "PreStats_CPCT12345678T_HJJLGCCXX_S1_L001_R2_001.fastq.gz.done"),
        catfile("CPCT12345678R", "logs", "Mapping_CPCT12345678R.done"),
        catfile("CPCT12345678T", "logs", "Mapping_CPCT12345678T.done"),
        catfile("CPCT12345678R", "logs", "PerLaneConvert_CPCT12345678R_HJJLGCCXX_S1_L001_001.done"),
        catfile("CPCT12345678T", "logs", "PerLaneConvert_CPCT12345678T_HJJLGCCXX_S1_L001_001.done"),
        catfile("CPCT12345678R", "logs", "Map_CPCT12345678R_HJJLGCCXX_S1_L001_001.done"),
        catfile("CPCT12345678T", "logs", "Map_CPCT12345678T_HJJLGCCXX_S1_L001_001.done"),
        catfile("CPCT12345678R", "logs", "DamageEstimate_CPCT12345678R.done"),
        catfile("CPCT12345678T", "logs", "DamageEstimate_CPCT12345678T.done"),
        catfile("CPCT12345678R", "logs", "Realignment_CPCT12345678R.done"),
        catfile("CPCT12345678R", "logs", "RealignmentCleanup_CPCT12345678R.done"),
        catfile("CPCT12345678R", "logs", "BaseRecalibration_CPCT12345678R.done"),
        catfile("CPCT12345678T", "logs", "Realignment_CPCT12345678T.done"),
        catfile("CPCT12345678T", "logs", "RealignmentCleanup_CPCT12345678T.done"),
        catfile("CPCT12345678T", "logs", "BaseRecalibration_CPCT12345678T.done"),
        catfile("CPCT12345678R", "logs", "BamPrep_CPCT12345678R.done"),
        catfile("CPCT12345678T", "logs", "BamPrep_CPCT12345678T.done"),
        catfile("somaticVariants", "CPCT12345678R_CPCT12345678T", "logs", "Strelka.done"),
        catfile("somaticVariants", "CPCT12345678R_CPCT12345678T", "logs", "Somatic_CPCT12345678R_CPCT12345678T.done"),
        catfile("structuralVariants", "gridss", "CPCT12345678R_CPCT12345678T", "logs", "Gridss_CPCT12345678R_CPCT12345678T.done"),
    );
    make_path(
        map {
            my ($name, $directory) = fileparse($_);
            $directory;
        } @done_files
    );
    touch @done_files;
    return;
}

sub testPipeline {
    my ($test_create_config, $test_pipeline, $ini_file, $mode, $done_files) = @_;

    $ini_file = fileparse($ini_file);
    my $test_description = "$ini_file ($mode mode" . ($done_files ? " with .done files)" : ")");
    my $output_dir = File::Temp->newdir();
    my $data_dir = catfile("t", "data", $mode);

    $test_create_config->run(args => "-iniFile ${ini_file} -${mode}Dir $data_dir -outputDir $output_dir");
    is($?, 0, "$test_description created config successfully") or diag $test_create_config->stderr;

    my $config_file = catfile($output_dir, "settings.config");
    $test_create_config->write(catfile($output_dir, "metadata"), <<"_METADATA_");
{
    "ref_sample": "CPCT12345678R",
    "tumor_sample": "CPCT12345678T"
}
_METADATA_

    my $config_dir = File::Temp->newdir();
    my $temp_file = File::Temp->new(DIR => $config_dir);
    my $temp_dir = File::Temp->newdir(DIR => $config_dir);
    setupTestConfig($test_create_config, $config_file, $temp_file, $temp_dir);

    setupDoneFiles($output_dir) if ($done_files);
    $test_pipeline->run(args => $config_file);

    is($?, 0, "$test_description pipeline ran successfully") or diag $test_pipeline->stderr;
    my $stdout = $test_pipeline->stdout;
    my $stderr = $test_pipeline->stderr;
    file_empty_ok(catfile($output_dir, "run.lock"), "$test_description lock file created");
    my ($stdout_log_file) = glob catfile($output_dir, "logs", "submitlog_*.out");
    my ($stderr_log_file) = glob catfile($output_dir, "logs", "submitlog_*.err");
    isnt($stdout_log_file, undef, "$test_description found stdout log file");
    isnt($stderr_log_file, undef, "$test_description found stderr log file");
    file_ok($stdout_log_file, $stdout, "$test_description stdout logged to file");
    file_ok($stderr_log_file, $stderr, "$test_description stderr logged to file");
    file_not_empty_ok(catfile($output_dir, "logs", "links.json"), "$test_description produced links.json");

    my @jobs = File::Find::Rule->file() #
        ->name("*.sh")                  #
        ->in($output_dir);              #

    foreach my $job (@jobs) {
        my $job_script = fileparse($job);
        my $test_job = Test::Cmd->new(prog => "/usr/bin/env", workdir => "");
        $test_job->run(args => "bash -n $job");
        is($?, 0, "$test_description $job_script job has valid bash syntax") or diag $test_job->stderr;
        # KODU: SC2034,SC2036,SC2086,SC2016 ignored for GRIDSS
        # KODU: SC2046,SC2005,SC2012 ignored for germline rerun
        $test_job->run(args => "shellcheck --exclude SC1091,SC2050,SC2129,SC1117,SC2034,SC2036,SC2086,SC2016,SC2010,SC2046,SC2005,SC2012 $job");
        is($?, 0, "$test_description $job_script job passes shellcheck") or diag $test_job->stdout;
        (my $job_name = $job_script) =~ s/\.sh$//;
        if (not $done_files or $job_name =~ /^PipelineCheck/) {
            like($stdout, qr/^Your job [0-9]+ \("$job_name"\) has been submitted$/m, "$job_script job submitted");
        } else {
            # SABR: loop will not be entered if jobs (correctly) not created, but test will make failure clearer
            unlike($stdout, qr/^Your job [0-9]+ \("$job_name"\) has been submitted$/m, "$job_script job not submitted");
        }
    }
    return;
}

my $test_create_config = Test::Cmd->new(prog => catfile("bin", "create_config.pl"), workdir => "");
my $test_pipeline = Test::Cmd->new(prog => catfile("bin", "pipeline.pl"), workdir => "");

$test_pipeline->run();
is($?, 0, "usage successful exit status");
like($test_pipeline->stderr, qr/Usage: .*\/pipeline.pl configurationFile\.conf/, "usage shown on stderr");

$test_pipeline->run(args => $test_pipeline->devnull());
my @lines = $test_pipeline->stderr;
isnt($?, 0, "error with empty config");
ok($test_pipeline->match([ @lines[ 0 .. -1 ] ], [qr/^ERROR:/] x $#lines), "warnings for failed checks");
like($lines[-1], qr/One or more options not found or invalid in config files/, "summary of check failure");

my @ini_modes = glob catfile("settings", "*.ini");
foreach my $with_done_files (0, 1) {
    foreach my $ini_mode (@ini_modes) {
        if (index($ini_mode, "bam") == -1) {
            testPipeline($test_create_config, $test_pipeline, $ini_mode, "fastq", $with_done_files);
        }
    }

SKIP: {
        skip "no SAMTOOLS_PATH set", scalar @ini_modes if not $ENV{SAMTOOLS_PATH};

        my @sam_files = File::Find::Rule->file() #
            ->name("*.sam")                      #
            ->in(catfile("t", "data"));          #

        for my $sam_file (@sam_files) {
            Util::convertToBam($sam_file, $with_done_files);
        }

        foreach my $ini_mode (@ini_modes) {
            testPipeline($test_create_config, $test_pipeline, $ini_mode, "bam", $with_done_files);
        }
    }
}

done_testing();
