//
// Convert BAM to CRAM, create index and calculate statistics
//

include { CRUMBLE           } from '../../modules/nf-core/crumble/main'
include { SAMTOOLS_VIEW     } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_STATS    } from '../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_FLAGSTAT } from '../../modules/nf-core/samtools/flagstat/main'
include { SAMTOOLS_IDXSTATS } from '../../modules/nf-core/samtools/idxstats/main'


workflow CONVERT_STATS {
    take:
    bam      // channel: [ val(meta), /path/to/bam, /path/to/bai]
    fasta    // channel: [ val(meta), /path/to/fasta ]


    main:
    ch_versions = Channel.empty()

    // Compress the quality scores of Illumina and PacBio CCS alignments
    bam
    | branch {
        meta, bam, bai ->
            run_crumble : meta.datatype == "hic" || meta.datatype == "illumina" || meta.datatype == "pacbio"
                          [meta, bam]
            no_crumble: true
    }
    | set { ch_bams }

    CRUMBLE ( ch_bams.run_crumble, [], [] )
    ch_versions = ch_versions.mix ( CRUMBLE.out.versions )


    // Convert BAM to CRAM
    CRUMBLE.out.bam
    | map { meta, bam -> [meta, bam, []] }
    | mix ( ch_bams.no_crumble )
    | set { ch_bams_for_conversion }

    SAMTOOLS_VIEW ( ch_bams_for_conversion, fasta, [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_VIEW.out.versions.first() )

    // Combine CRAM and CRAI into one channel
    SAMTOOLS_VIEW.out.cram
    | join ( SAMTOOLS_VIEW.out.crai )
    | set { ch_cram_crai }


    // Calculate statistics
    SAMTOOLS_STATS ( ch_cram_crai, fasta )
    ch_versions = ch_versions.mix ( SAMTOOLS_STATS.out.versions.first() )


    // Calculate statistics based on flag values
    SAMTOOLS_FLAGSTAT ( ch_cram_crai )
    ch_versions = ch_versions.mix ( SAMTOOLS_FLAGSTAT.out.versions.first() )


    // Calculate index statistics
    SAMTOOLS_IDXSTATS ( ch_cram_crai )
    ch_versions = ch_versions.mix ( SAMTOOLS_IDXSTATS.out.versions.first() )


    emit:
    cram     = SAMTOOLS_VIEW.out.cram            // channel: [ val(meta), /path/to/cram ]
    crai     = SAMTOOLS_VIEW.out.crai            // channel: [ val(meta), /path/to/crai ]
    stats    = SAMTOOLS_STATS.out.stats          // channel: [ val(meta), /path/to/stats ]
    flagstat = SAMTOOLS_FLAGSTAT.out.flagstat    // channel: [ val(meta), /path/to/idxstats ]
    idxstats = SAMTOOLS_IDXSTATS.out.idxstats    // channel: [ val(meta), /path/to/flagstat ]
    versions = ch_versions                       // channel: [ versions.yml ]
}
