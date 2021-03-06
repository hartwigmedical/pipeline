package org.broadinstitute.gatk.queue.qscripts

import org.broadinstitute.gatk.queue.QScript
import org.broadinstitute.gatk.queue.extensions.gatk._

import org.broadinstitute.gatk.tools.walkers.haplotypecaller.ReferenceConfidenceMode
import org.broadinstitute.gatk.utils.commandline.ClassType
import org.broadinstitute.gatk.utils.variant.GATKVCFIndexType

class GermlineCaller extends QScript {
    qscript =>

    @Input(doc="The reference file for the bam files.", shortName="R", required=true)
    var referenceFile: File = _

    @Input(doc="One or more bam files.", shortName="I", required=true)
    var bamFiles: List[File] = Nil

    @Input(doc="Output core filename.", shortName="O", required=true)
    var out: File = _

    @Argument(doc="Maxmem.", shortName="mem", required=true)
    var maxMem: Int = _

    @Argument(doc="Number of cpu threads per data thread", shortName="nct", required=true)
    var numCPUThreads: Int = _

    @Argument(doc="Number of scatters", shortName="nsc", required=true)
    var numScatters: Int = _

    @Argument(doc="Minimum phred-scaled confidence to call variants", shortName="stand_call_conf", required=true)
    var standCallConf: Int = _

    @Input(doc="An optional file with known SNP sites.", shortName="D", required=false)
    var dbsnpFile: File = _

    @Argument(doc="Ploidy (number of chromosomes) per sample", shortName="ploidy", required=false)
    var samplePloidy: Int = 2

    @Argument(doc="Exclusive upper bounds for reference confidence GQ bands", shortName="gqb", required=false)
    @ClassType(classOf[Int])
    var GVCFGQBands: Seq[Int] = List(5,10,15,20,30,40,50,60)

    def script() {
			var gvcfFiles : List[File] = Nil

			for (bamFile <- bamFiles) {
					val haplotypeCaller = new HaplotypeCaller

					haplotypeCaller.input_file :+= bamFile
					haplotypeCaller.reference_sequence = referenceFile
					haplotypeCaller.out = swapExt(bamFile, "bam", "g.vcf.gz")

					haplotypeCaller.scatterCount = numScatters
					haplotypeCaller.memoryLimit = maxMem
					haplotypeCaller.num_cpu_threads_per_data_thread = numCPUThreads

					haplotypeCaller.stand_call_conf = standCallConf

					haplotypeCaller.emitRefConfidence = ReferenceConfidenceMode.GVCF
					haplotypeCaller.GVCFGQBands = GVCFGQBands
					haplotypeCaller.variant_index_type = GATKVCFIndexType.LINEAR
					haplotypeCaller.variant_index_parameter = 128000
					haplotypeCaller.sample_ploidy = samplePloidy

					gvcfFiles :+= haplotypeCaller.out
					add(haplotypeCaller)
			}

			val genotypeGVCFs = new GenotypeGVCFs

			genotypeGVCFs.V = gvcfFiles
			genotypeGVCFs.reference_sequence = referenceFile
			genotypeGVCFs.scatterCount = numScatters
			genotypeGVCFs.num_threads = numCPUThreads //for now use numCPUThreads, maybe change to new numDataThreads variable

			genotypeGVCFs.out = qscript.out + ".raw_variants.vcf"

			if (dbsnpFile != null) {
					genotypeGVCFs.D = dbsnpFile
			}

			add(genotypeGVCFs)
    }
}
