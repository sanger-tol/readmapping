//
// Align Nanopore read files against the genome
//

include { MINIMAP2_ALIGN } from '../../modules/local/minimap2/align'
include { MARKDUP_STATS  } from '../../subworkflows/local/markdup_stats'

workflow ALIGN_ONT {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/mmi
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Align Fastq to Genome
    MINIMAP2_ALIGN ( reads, fasta, index )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Merge, markdup, convert, and stats
    MARKDUP_STATS ( MINIMAP2_ALIGN.out.sam, fasta )
    ch_versions = ch_versions.mix(MARKDUP_STATS.out.versions)

    emit:
    cram = MARKDUP_STATS.out.cram
    crai = MARKDUP_STATS.out.crai
    stats = MARKDUP_STATS.out.stats
    idxstats = MARKDUP_STATS.out.idxstats
    flagstat = MARKDUP_STATS.out.flagstat

    versions = ch_versions
}
