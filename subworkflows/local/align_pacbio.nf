//
// Align PacBio read files against the genome
//

include { FILTER_PACBIO  } from '../../subworkflows/local/filter_pacbio'
include { MINIMAP2_ALIGN } from '../../modules/nf-core/modules/nf-core/minimap2/align/main'
include { MERGE_STATS    } from '../../subworkflows/local/merge_stats'

workflow ALIGN_PACBIO {
    take:
    fasta // channel: /path/to/fasta
    reads // channel: [ val(meta), [ datafile ] ]
    db    // channel: /path/to/vector_db

    main:
    ch_versions = Channel.empty()

    // Filter BAM and output as FASTQ
    FILTER_PACBIO ( reads, db )
    ch_versions = ch_versions.mix(FILTER_PACBIO.out.versions)

    // Align Fastq to Genome
    MINIMAP2_ALIGN ( FILTER_PACBIO.out.fastq, fasta, true, false, false )
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
