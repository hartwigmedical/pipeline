package HMF::Pipeline::Job::Bam;

use FindBin::libs;
use discipline;

use File::Basename;
use File::Spec::Functions;

use HMF::Pipeline::Config qw(createDirs);
use HMF::Pipeline::Job qw(fromTemplate);
use HMF::Pipeline::Sge qw(qsubTemplate jobNative qsubJava);

use parent qw(Exporter);
our @EXPORT_OK = qw(
    slice
    flagstat
    diff
    prePostSliceAndDiff
    operationWithSliceChecks
);


sub slice {
    my ($sample, $sample_bam, $sliced_bam, $bed_name, $hold_jids, $dirs, $opt) = @_;

    my $slice_name = fileparse($sliced_bam);
    return fromTemplate(
        "SliceBam",
        $slice_name,
        qsubTemplate($opt, "FLAGSTAT"),
        $hold_jids,
        $dirs,
        $opt,
        sample => $sample,
        sample_bam => $sample_bam,
        input_bam => catfile($dirs->{mapping}, $sample_bam),
        bed_file => catfile($opt->{OUTPUT_DIR}, "settings", "slicing", $bed_name),
        sliced_bam => catfile($dirs->{mapping}, $sliced_bam),
    );
}

sub flagstat {
    my ($sample, $sample_bam_path, $sample_flagstat_path, $hold_jids, $dirs, $opt) = @_;

    my $flagstat_name = fileparse($sample_flagstat_path);
    return fromTemplate(
        "Flagstat",
        $flagstat_name,
        qsubTemplate($opt, "FLAGSTAT"),
        $hold_jids,
        $dirs,
        $opt,
        sample => $sample,
        sample_bam_path => $sample_bam_path,
        sample_flagstat_path => $sample_flagstat_path,
    );
}

sub diff {
    my ($sample, $input_bam1, $input_bam2, $diff_name, $hold_jids, $dirs, $opt) = @_;

    return fromTemplate(
        "DiffBams",
        $diff_name,
        qsubTemplate($opt, "FLAGSTAT"),
        $hold_jids,
        $dirs,
        $opt,
        sample => $sample,
        diff_name => $diff_name,
        input_bam1 => catfile($dirs->{mapping}, $input_bam1),
        input_bam2 => catfile($dirs->{mapping}, $input_bam2),
        output_diff => catfile($dirs->{mapping}, $diff_name),
    );
}

sub prePostSliceAndDiff {
    my ($sample, $operation, $pre_bam, $post_bam, $hold_jids, $dirs, $opt) = @_;

    (my $pre_sliced_bam = $pre_bam) =~ s/\.bam$/.qc.pre${operation}.sliced.bam/;
    (my $post_sliced_bam = $pre_bam) =~ s/\.bam$/.qc.post${operation}.sliced.bam/;
    (my $post_sliced_flagstat = $pre_bam) =~ s/\.bam$/.qc.post${operation}.sliced.flagstat/;
    (my $pre_post_diff = $pre_bam) =~ s/\.bam$/.qc.prepost${operation}.diff/;

    my $post_sliced_bam_path = catfile($dirs->{mapping}, $post_sliced_bam);
    my $post_sliced_flagstat_path = catfile($dirs->{mapping}, $post_sliced_flagstat);

    my $pre_job_id = slice($sample, $pre_bam, $pre_sliced_bam, "HealthCheck_Slicing.bed", $hold_jids, $dirs, $opt);
    my $post_job_id = slice($sample, $post_bam, $post_sliced_bam, "HealthCheck_Slicing.bed", $hold_jids, $dirs, $opt);
    my $diff_job_id = diff($sample, $pre_sliced_bam, $post_sliced_bam, $pre_post_diff, [ $pre_job_id, $post_job_id ], $dirs, $opt);
    my $flagstat_job_id = flagstat($sample, $post_sliced_bam_path, $post_sliced_flagstat_path, [$post_job_id], $dirs, $opt);

    return [ $diff_job_id, $flagstat_job_id ];
}

sub operationWithSliceChecks {
    my ($job_template, $sample, $known_files, $post_tag, $slice_tag, $opt) = @_;

    my $sample_bam = $opt->{BAM_FILES}->{$sample};
    (my $sample_flagstat = $sample_bam) =~ s/\.bam$/.flagstat/;
    (my $post_bam = $sample_bam) =~ s/\.bam$/.${post_tag}.bam/;
    (my $post_bai = $sample_bam) =~ s/\.bam$/.${post_tag}.bai/;
    (my $post_flagstat = $sample_bam) =~ s/\.bam$/.${post_tag}.flagstat/;
    (my $cpct_sliced_bam = $sample_bam) =~ s/\.bam$/.${post_tag}.sliced.bam/;

    $opt->{BAM_FILES}->{$sample} = $post_bam;

    my $out_dir = catfile($opt->{OUTPUT_DIR}, $sample);
    my $dirs = createDirs($out_dir, mapping => "mapping");
    my $sample_bam_path = catfile($dirs->{mapping}, $sample_bam);
    say "\t${sample_bam_path}";

    my $job_id = fromTemplate(
        $job_template,
        $sample,
        qsubJava($opt, uc $job_template . "_MASTER"),
        $opt->{RUNNING_JOBS}->{$sample},
        $dirs,
        $opt,
        sample => $sample,
        sample_bam => $sample_bam,
        sample_bam_path => $sample_bam_path,
        job_native => jobNative($opt, uc $job_template),
        known_files => $known_files,
    );

    return unless $job_id;

    my $flagstat_job_id = flagstat($sample, catfile($dirs->{tmp}, $post_bam), catfile($dirs->{mapping}, $post_flagstat), [$job_id], $dirs, $opt);

    my $check_job_id = fromTemplate(
        "ReadCountCheck",
        $sample,
        qsubTemplate($opt, "FLAGSTAT"),
        [$flagstat_job_id],
        $dirs,
        $opt,
        sample => $sample,
        pre_flagstat_path => catfile($dirs->{mapping}, $sample_flagstat),
        post_flagstat_path => catfile($dirs->{mapping}, $post_flagstat),
        post_bam => $post_bam,
        post_bai => $post_bai,
        success_template => "${job_template}Success.tt",
    );

    push @{$opt->{RUNNING_JOBS}->{$sample}}, $check_job_id;

    my $qc_job_ids = prePostSliceAndDiff($sample, $slice_tag, $sample_bam, $post_bam, [$check_job_id], $dirs, $opt);
    my $cpct_job_id = slice($sample, $post_bam, $cpct_sliced_bam, "CPCT_Slicing.bed", [$check_job_id], $dirs, $opt);

    push @{$opt->{RUNNING_JOBS}->{slicing}}, @{$qc_job_ids}, $cpct_job_id;
    return;
}

1;