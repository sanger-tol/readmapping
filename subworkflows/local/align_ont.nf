//
// Align Nanopore read files against the genome
//

include { MINIMAP2_ALIGN } from '../../modules/nf-core/minimap2/align/main'
include { MERGE_STATS    } from '../../subworkflows/local/merge_stats'

workflow ALIGN_ONT {
    take:
    fasta // channel: /path/to/fasta
    reads // channel: [ val(meta), [ datafile ] ]

    main:
    ch_versions = Channel.empty()

    // Align Fastq to Genome
    MINIMAP2_ALIGN ( reads, fasta, true, false, false )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Merge, markdup, convert, and stats
    MERGE_STATS ( MINIMAP2_ALIGN.out.bam, fasta )
    ch_versions = ch_versions.mix(MERGE_STATS.out.versions)

    emit:
    cram     = MERGE_STATS.out.cram
    crai     = MERGE_STATS.out.crai
    stats    = MERGE_STATS.out.stats
    idxstats = MERGE_STATS.out.idxstats
    flagstat = MERGE_STATS.out.flagstat
    versions = ch_versions
}
