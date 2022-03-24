//
// Align HiC read files against the genome
//

include { SAMTOOLS_FASTQ } from '../../modules/local/samtools/fastq'
include { BWAMEM2_MEM    } from '../../modules/nf-core/modules/bwamem2/mem/main'
include { STATS_MARKDUP  } from '../../subworkflows/local/stats_markdup'

workflow ALIGN_HIC {
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
    BWAMEM2_MEM ( SAMTOOLS_FASTQ.out.fastq, index, true )
    ch_versions = ch_versions.mix(BWAMEM2_MEM.out.versions.first())

    // Convert to CRAM, calculate indices and statistics, merge, markdup, and repeat
    STATS_MARKDUP ( BWAMEM2_MEM.out.bam, fasta )
    ch_versions = ch_versions.mix(STATS_MARKDUP.out.versions)

    emit:
    cram1 = STATS_MARKDUP.out.cram1
    crai1 = STATS_MARKDUP.out.crai1
    stats1 = STATS_MARKDUP.out.stats1
    idxstats1 = STATS_MARKDUP.out.idxstats1
    flagstat1 = STATS_MARKDUP.out.flagstat1

    cram2 = STATS_MARKDUP.out.cram2
    crai2 = STATS_MARKDUP.out.crai2
    stats2 = STATS_MARKDUP.out.stats2
    idxstats2 = STATS_MARKDUP.out.idxstats2
    flagstat2 = STATS_MARKDUP.out.flagstat2

    cram3 = STATS_MARKDUP.out.cram3
    crai3 = STATS_MARKDUP.out.crai3
    stats3 = STATS_MARKDUP.out.stats3
    idxstats3 = STATS_MARKDUP.out.idxstats3
    flagstat3 = STATS_MARKDUP.out.flagstat3

    versions = ch_versions
}
