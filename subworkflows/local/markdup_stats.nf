//
// Merge and Markdup all alignments at specimen level
// Convert to CRAM and calculate statistics
//

include { SAMTOOLS_SORT } from '../../modules/nf-core/samtools/sort/main'
include { MARKDUPLICATE } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS } from '../../subworkflows/local/convert_stats'


workflow MARKDUP_STATS {
    take:
    aln      // channel: [ val(meta), /path/to/bam ]
    fasta    // channel: [ val(meta), /path/to/fasta ]


    main:
    ch_versions = Channel.empty()


    // Sort BAM file
    SAMTOOLS_SORT ( aln )
    ch_versions = ch_versions.mix ( SAMTOOLS_SORT.out.versions.first() )


    // Collect all BWAMEM2 output by sample name
    SAMTOOLS_SORT.out.bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], bam] }
    | groupTuple( by: [0] )
    | set { ch_bams }


    // Mark duplicates
    MARKDUPLICATE ( ch_bams )
    ch_versions = ch_versions.mix ( MARKDUPLICATE.out.versions )


    // Convert merged BAM to CRAM and calculate indices and statistics
    MARKDUPLICATE.out.bam
    | map { meta, bam -> [ meta, bam, [] ] }
    | set { ch_stat }

    CONVERT_STATS ( ch_stat, fasta )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )


    emit:
    cram     = CONVERT_STATS.out.cram        // channel: [ val(meta), /path/to/cram ]
    crai     = CONVERT_STATS.out.crai        // channel: [ val(meta), /path/to/crai ]
    stats    = CONVERT_STATS.out.stats       // channel: [ val(meta), /path/to/stats ]
    idxstats = CONVERT_STATS.out.idxstats    // channel: [ val(meta), /path/to/idxstats ]
    flagstat = CONVERT_STATS.out.flagstat    // channel: [ val(meta), /path/to/flagstat ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
