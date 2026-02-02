//
// Convert BAM to CRAM, create index and calculate statistics
//


// MODULE: local modules
include { SAMTOOLS_REHEADER as SAMTOOLS_REHEADER_BAM    } from '../../modules/local/samtools_replaceheader'
include { SAMTOOLS_REHEADER as SAMTOOLS_REHEADER_CRAM   } from '../../modules/local/samtools_replaceheader'
include { CHANGE_NAME                                   } from '../../modules/local/change_name'

// MODULE: nf-core modules
include { CRUMBLE                           } from '../../modules/nf-core/crumble/main'
include { SAMTOOLS_VIEW as SAMTOOLS_CRAM    } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_INDEX                    } from '../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_STATS                    } from '../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_FLAGSTAT                 } from '../../modules/nf-core/samtools/flagstat/main'
include { SAMTOOLS_IDXSTATS                 } from '../../modules/nf-core/samtools/idxstats/main'
include { BLOBTK_DEPTH                      } from '../../modules/local/blobtk_depth'
include { TABIX_BGZIP as BGZIP_BEDGRAPH     } from '../../modules/nf-core/tabix/bgzip/main'
include { GUNZIP as GZIP_STATS              } from '../../modules/local/gzip'


workflow CONVERT_STATS {
    take:
    bam      // channel: [ val(meta), /path/to/bam, /path/to/bai ]
    fasta    // channel: [ val(meta), /path/to/fasta ]
    header   // channel: /path/to/header.sam


    main:
    ch_versions = channel.empty()

    // Split outfmt parameter into a list
    def outfmt_options = params.outfmt.split(',').collect { fmt -> fmt.trim() }

    // (Optionally) Compress the quality scores of Illumina and PacBio CCS alignments
    if ( params.compression == "crumble" ) {
        bam
        .branch {
            meta, _bam ->
                run_crumble: meta.datatype == "hic" || meta.datatype == "illumina" || meta.datatype == "pacbio"
                no_crumble: true
        }
        .set { crumble_selector }

        CRUMBLE ( crumble_selector.run_crumble, [], [] )
        ch_versions = ch_versions.mix( CRUMBLE.out.versions )

        CRUMBLE.out.bam
        .mix( crumble_selector.no_crumble )
        .set { ch_bams_for_renaming }
    } else {
        ch_bams_for_renaming = bam
    }

    // Change name of BAM files to final name for publishing
    CHANGE_NAME ( ch_bams_for_renaming, fasta )

    CHANGE_NAME.out.file
    .map { meta, bam_file -> [meta, bam_file, []] }
    .set { ch_renamed_bams }

    // (Optionally) convert to CRAM if it's specified in outfmt
    ch_cram = channel.empty()
    ch_crai = channel.empty()

    if ( "cram" in outfmt_options ) {
        SAMTOOLS_CRAM ( ch_renamed_bams, fasta, [], [] )

        // Combine CRAM and CRAI into one channel
        ch_cram = SAMTOOLS_CRAM.out.cram
        ch_crai = SAMTOOLS_CRAM.out.crai
        ch_for_stats = ch_cram.join ( ch_crai )
    }

    // Re-generate BAM index if BAM is in outfmt
    ch_bam = channel.empty()
    ch_bai = channel.empty()

    if ( "bam" in outfmt_options ) {
        // Reindex BAM
        SAMTOOLS_INDEX ( CHANGE_NAME.out.file )
        ch_versions = ch_versions.mix ( SAMTOOLS_INDEX.out.versions.first() )

        // Set the BAM and BAI channels for emission
        ch_bam = CHANGE_NAME.out.file
        ch_bai = SAMTOOLS_INDEX.out.bai.mix ( SAMTOOLS_INDEX.out.csi )

        if ( !('cram' in outfmt_options) ) {
            ch_for_stats = ch_bam.join ( ch_bai )
        }

    }

    // Optionally insert params.header information to bams
    if ( params.header ) {
        ch_bam = SAMTOOLS_REHEADER_BAM ( ch_bam, header.first() ).bam
        ch_cram = SAMTOOLS_REHEADER_CRAM ( ch_cram, header.first() ).cram
        ch_versions = ch_versions.mix ( SAMTOOLS_REHEADER_BAM.out.versions )
                                .mix ( SAMTOOLS_REHEADER_CRAM.out.versions )
    }

    // Calculate read depth
    BLOBTK_DEPTH ( ch_renamed_bams )
    ch_versions = ch_versions.mix ( BLOBTK_DEPTH.out.versions.first() )

    BGZIP_BEDGRAPH ( BLOBTK_DEPTH.out.bedgraph )
    ch_versions = ch_versions.mix ( BGZIP_BEDGRAPH.out.versions.first() )

    // Calculate statistics
    SAMTOOLS_STATS ( ch_for_stats, [[], []] )

    GZIP_STATS  ( SAMTOOLS_STATS.out.stats )
    ch_versions = ch_versions.mix ( GZIP_STATS.out.versions.first() )

    // Calculate statistics based on flag values
    SAMTOOLS_FLAGSTAT ( ch_for_stats )
    ch_versions = ch_versions.mix ( SAMTOOLS_FLAGSTAT.out.versions.first() )

    // Calculate index statistics
    SAMTOOLS_IDXSTATS ( ch_for_stats )
    ch_versions = ch_versions.mix ( SAMTOOLS_IDXSTATS.out.versions.first() )


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
