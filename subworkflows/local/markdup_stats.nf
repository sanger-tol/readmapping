//
// Merge and Markdup all alignments at specimen level
// Convert to CRAM and calculate statistics
//

include { SAMTOOLS_MERGE    } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORT     } from '../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_SORMADUP } from '../../modules/local/samtools_sormadup'
include { CONVERT_STATS     } from '../../subworkflows/local/convert_stats'


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
    | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], meta.read_count, bam] }
    | groupTuple( by: [0] )
    | map { meta, read_counts, bams -> [meta + [read_count: read_counts.sum()], bams] }
    | branch {
        meta, bams ->
            single_bam: bams.size() == 1
            multi_bams: true
    }
    | set { ch_bams }


    // Merge, but only if there is more than 1 file
    SAMTOOLS_MERGE ( ch_bams.multi_bams, [ [], [] ], [ [], [] ] )
    ch_versions = ch_versions.mix ( SAMTOOLS_MERGE.out.versions.first() )


    SAMTOOLS_MERGE.out.bam
    | mix ( ch_bams.single_bam )
    | set { ch_bam }


    // Mark duplicates
    SAMTOOLS_SORMADUP ( ch_bam, fasta )
    ch_versions = ch_versions.mix ( SAMTOOLS_SORMADUP.out.versions )


    // Convert merged BAM to CRAM and calculate indices and statistics
    SAMTOOLS_SORMADUP.out.bam
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
