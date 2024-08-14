//
// Convert BAM to CRAM, create index and calculate statistics
//

include { CRUMBLE                           } from '../../modules/nf-core/crumble/main'
include { SAMTOOLS_VIEW as SAMTOOLS_CRAM    } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_VIEW as SAMTOOLS_REINDEX } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_STATS                    } from '../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_FLAGSTAT                 } from '../../modules/nf-core/samtools/flagstat/main'
include { SAMTOOLS_IDXSTATS                 } from '../../modules/nf-core/samtools/idxstats/main'


workflow CONVERT_STATS {
    take:
    bam      // channel: [ val(meta), /path/to/bam, /path/to/bai ]
    fasta    // channel: [ val(meta), /path/to/fasta ]

    main:
    ch_versions = Channel.empty()


    // Split outfmt parameter into a list
    def outfmt_options = params.outfmt.split(',').collect { it.trim() }


    // (Optionally) Compress the quality scores of Illumina and PacBio CCS alignments
    if ( params.compression == "crumble" ) {
        bam
        | branch {
            meta, bam ->
                run_crumble: meta.datatype == "hic" || meta.datatype == "illumina" || meta.datatype == "pacbio"
                no_crumble: true
        }
        | set { ch_bams }

        CRUMBLE ( ch_bams.run_crumble, [], [] )
        ch_versions = ch_versions.mix( CRUMBLE.out.versions )

        // Convert BAM to CRAM
        CRUMBLE.out.bam
        | mix( ch_bams.no_crumble )
        | map { meta, bam -> [meta, bam, []] }
        | set { ch_bams_for_conversion }

    } else {
        bam
        | map { meta, bam -> [meta, bam, []] }
        | set { ch_bams_for_conversion }
    }


    // (Optionally) convert to CRAM if it's specified in outfmt
    ch_cram = Channel.empty()
    ch_crai = Channel.empty()

    if ("cram" in outfmt_options) {
        SAMTOOLS_CRAM ( ch_bams_for_conversion, fasta, [] )
        ch_versions = ch_versions.mix( SAMTOOLS_CRAM.out.versions.first() )

        // Combine CRAM and CRAI into one channel
        ch_cram = SAMTOOLS_CRAM.out.cram
        ch_crai = SAMTOOLS_CRAM.out.crai
    }


    // Re-generate BAM index if BAM is in outfmt
    def ch_data_for_stats
    if ("cram" in outfmt_options) {
        ch_data_for_stats = ch_cram.join( ch_crai )
    } else {
        ch_data_for_stats = ch_bams_for_conversion
    }

    ch_bam = Channel.empty()
    ch_bai = Channel.empty()

    if ("bam" in outfmt_options) {
        // Re-generate BAM index
        SAMTOOLS_REINDEX ( ch_bams_for_conversion, fasta, [] )
        ch_versions = ch_versions.mix( SAMTOOLS_REINDEX.out.versions.first() )

        // Set the BAM and BAI channels for emission
        ch_bam = SAMTOOLS_REINDEX.out.bam
        ch_bai = SAMTOOLS_REINDEX.out.bai

        // If using BAM for stats, use the reindexed BAM
        if ( !("cram" in outfmt_options) ) {
            ch_data_for_stats = ch_bam.join ( ch_bai )
        }
    }


    // Calculate statistics
    SAMTOOLS_STATS ( ch_data_for_stats, fasta )
    ch_versions = ch_versions.mix( SAMTOOLS_STATS.out.versions.first() )


    // Calculate statistics based on flag values
    SAMTOOLS_FLAGSTAT ( ch_data_for_stats )
    ch_versions = ch_versions.mix( SAMTOOLS_FLAGSTAT.out.versions.first() )


    // Calculate index statistics
    SAMTOOLS_IDXSTATS ( ch_data_for_stats )
    ch_versions = ch_versions.mix( SAMTOOLS_IDXSTATS.out.versions.first() )

    emit:
    bam      = ch_bam                               // channel: [ val(meta), /path/to/bam ] (optional)
    bai      = ch_bai                               // channel: [ val(meta), /path/to/bai ] (optional)
    cram     = ch_cram                              // channel: [ val(meta), /path/to/cram ] (optional)
    crai     = ch_crai                              // channel: [ val(meta), /path/to/crai ] (optional)
    stats    = SAMTOOLS_STATS.out.stats             // channel: [ val(meta), /path/to/stats ]
    flagstat = SAMTOOLS_FLAGSTAT.out.flagstat       // channel: [ val(meta), /path/to/flagstat ]
    idxstats = SAMTOOLS_IDXSTATS.out.idxstats       // channel: [ val(meta), /path/to/idxstats ]
    versions = ch_versions                          // channel: [ versions.yml ]
}
