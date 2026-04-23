//
// Convert BAM to CRAM, create index and calculate statistics
//


// MODULE: local modules
include { SAMTOOLS_REHEADER as SAMTOOLS_REHEADER_BAM    } from '../../modules/local/samtools/reheader/samtools_replaceheader'
include { SAMTOOLS_REHEADER as SAMTOOLS_REHEADER_CRAM   } from '../../modules/local/samtools/reheader/samtools_replaceheader'
include { CHANGE_NAME                                   } from '../../modules/local/change_name'

// MODULE: nf-core modules
include { BLOBTK_DEPTH                              } from '../../modules/nf-core/blobtk/depth/main'
include { CRUMBLE                                   } from '../../modules/nf-core/crumble/main'
include { PIGZ_COMPRESS as GZIP_STATS               } from '../../modules/nf-core/pigz/compress/main'
include { SAMTOOLS_VIEW as SAMTOOLS_CRAM            } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_BAM      } from '../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_CRAM     } from '../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_STATS                            } from '../../modules/nf-core/samtools/stats/main'
include { SAMTOOLS_FLAGSTAT                         } from '../../modules/nf-core/samtools/flagstat/main'
include { SAMTOOLS_IDXSTATS                         } from '../../modules/nf-core/samtools/idxstats/main'
include { SAMTOOLS_BGZIP as BGZIP_BEDGRAPH          } from '../../modules/nf-core/samtools/bgzip/main'


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
        crumble_selector = bam
        .branch {
            meta, _bam ->
                run_crumble: meta.datatype == "hic" || meta.datatype == "illumina" || meta.datatype == "pacbio"
                no_crumble: true
        }

        CRUMBLE ( crumble_selector.run_crumble, [], [] )
        ch_versions = ch_versions.mix( CRUMBLE.out.versions )

        ch_bams_for_renaming = CRUMBLE.out.bam
        .mix( crumble_selector.no_crumble )
    } else {
        ch_bams_for_renaming = bam
    }

    // Change name of BAM files to final name for publishing
    CHANGE_NAME ( ch_bams_for_renaming, fasta )

    ch_renamed_bams = CHANGE_NAME.out.file
    .map { meta, bam_file -> [meta, bam_file, []] }

    // (Optionally) convert to CRAM if it's specified in outfmt
    ch_cram = channel.empty()
    ch_crai = channel.empty()

    fasta_dummy_idx = fasta.map { meta, fasta_file -> [ meta, fasta_file, [] ] }
    if ( "cram" in outfmt_options ) {
        SAMTOOLS_CRAM ( ch_renamed_bams, fasta_dummy_idx, [[],[]], [[],[]], "" )
        ch_cram = SAMTOOLS_CRAM.out.cram
        ch_crai = SAMTOOLS_CRAM.out.crai

        if ( params.header ) {
            SAMTOOLS_REHEADER_CRAM ( SAMTOOLS_CRAM.out.cram, header.first() )
            SAMTOOLS_INDEX_CRAM ( SAMTOOLS_REHEADER_CRAM.out.cram )
            ch_cram = SAMTOOLS_INDEX_CRAM.out.input
            ch_crai = SAMTOOLS_INDEX_CRAM.out.index
        }

        // Combine CRAM and CRAI into one channel
        ch_for_stats = ch_cram.join ( ch_crai )
    }

    // Re-generate BAM index if BAM is in outfmt
    ch_bam = channel.empty()
    ch_bai = channel.empty()

    if ( "bam" in outfmt_options ) {
        // Reindex BAM
        ch_bam = params.header ? SAMTOOLS_REHEADER_BAM ( CHANGE_NAME.out.file, header.first() ).bam : CHANGE_NAME.out.file
        SAMTOOLS_INDEX_BAM ( ch_bam )

        // Set the BAM and BAI channels for emission
        ch_bam = SAMTOOLS_INDEX_BAM.out.input
        ch_bai = SAMTOOLS_INDEX_BAM.out.index

        if ( !('cram' in outfmt_options) ) {
            ch_for_stats = ch_bam.join ( ch_bai )
        }

    }

    // Calculate read depth
    BLOBTK_DEPTH ( ch_renamed_bams )
    BGZIP_BEDGRAPH ( BLOBTK_DEPTH.out.bed )

    // Calculate statistics
    // Samtools stats does not need fasta for embed_ref CRAM
    SAMTOOLS_STATS ( ch_for_stats, [[],[],[]] )

    GZIP_STATS  ( SAMTOOLS_STATS.out.stats )

    // Calculate statistics based on flag values
    SAMTOOLS_FLAGSTAT ( ch_for_stats )

    // Calculate index statistics
    SAMTOOLS_IDXSTATS ( ch_for_stats )


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
