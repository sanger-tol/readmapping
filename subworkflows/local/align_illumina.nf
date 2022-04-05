//
// Align Illumina read files against the genome
//

include { SAMTOOLS_FASTQ } from '../../modules/local/samtools/fastq'
include { BWAMEM2_MEM    } from '../../modules/local/bwamem2/mem'
include { MARKDUP_STATS  } from '../../subworkflows/local/markdup_stats'

workflow ALIGN_ILLUMINA {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/bwamem2/
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Convert from CRAM to FASTQ
    SAMTOOLS_FASTQ ( reads )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())
    
    // Align Fastq to Genome
    BWAMEM2_MEM ( SAMTOOLS_FASTQ.out.fastq, index )
    ch_versions = ch_versions.mix(BWAMEM2_MEM.out.versions.first())

    // Merge, markdup, convert, and stats
    MARKDUP_STATS ( BWAMEM2_MEM.out.sam, fasta )
    ch_versions = ch_versions.mix(MARKDUP_STATS.out.versions)

    emit:
    cram = MARKDUP_STATS.out.cram
    crai = MARKDUP_STATS.out.crai
    stats = MARKDUP_STATS.out.stats
    idxstats = MARKDUP_STATS.out.idxstats
    flagstat = MARKDUP_STATS.out.flagstat

    versions = ch_versions
}
