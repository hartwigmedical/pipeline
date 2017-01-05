package HMF::Pipeline::GermlineAnnotation;

use FindBin::libs;
use discipline;

use File::Basename;
use File::Spec::Functions;

use HMF::Pipeline::Config qw(createDirs sampleBamsAndJobs recordPerSampleJob);
use HMF::Pipeline::Job qw(getId fromTemplate);
use HMF::Pipeline::Sge qw(qsubJava);
use HMF::Pipeline::Metadata;

use parent qw(Exporter);
our @EXPORT_OK = qw(run);


sub run {
    my ($opt) = @_;

    say "\n### SCHEDULING GERMLINE ANNOTATION ###";

    my (undef, $running_jobs) = sampleBamsAndJobs($opt);
    my $dirs = createDirs($opt->{OUTPUT_DIR});

    my $in_vcf = "$opt->{RUN_NAME}.filtered_variants.vcf";
    my $annotated_vcf = catfile($opt->{OUTPUT_DIR}, "$opt->{RUN_NAME}.filtered_variants.annotated.vcf");

    my $job_id = fromTemplate(
        "GermlineAnnotation",
        undef,
        qsubJava($opt, "ANNOTATE"),
        $running_jobs,
        $dirs,
        $opt,
        in_vcf => $in_vcf,
        pre_annotated_vcf => $in_vcf,
        annotated_vcf => $annotated_vcf,
    );

    HMF::Pipeline::Metadata::linkArtefact($annotated_vcf, "germline_vcf", $opt);
    HMF::Pipeline::Metadata::linkArtefact("${annotated_vcf}.idx", "germline_vcf_index", $opt);

    recordPerSampleJob($opt, $job_id) if $job_id;
    return;
}

1;