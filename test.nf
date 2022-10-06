#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

bwamem = "/path/to/bwamem.tar.gz"
fasta  = "/lustre/scratch123/tol/resources/nextflow/test-data/Meles_meles/assembly/release/mMelMel3.1_paternal_haplotype/GCA_922984935.2.subset.fasta.gz"

workflow {
    Channel.fromPath(fasta).map { file -> [ [ id: file.baseName.replaceFirst(/.fa.*/, "") ], file ] }.set { ch_asm }
    Channel.fromPath(bwamem).combine(ch_asm).map { bwa, meta, fa -> [ meta, bwa ] }.view()
}
