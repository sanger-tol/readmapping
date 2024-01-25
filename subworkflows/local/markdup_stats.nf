//
// Merge and Markdup all alignments at specimen level
// Convert to CRAM and calculate statistics
//

include { SAMTOOLS_MERGE    } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORMADUP } from '../../modules/local/samtools_sormadup'


workflow MARKDUP_STATS {
    take:
    aln      // channel: [ val(meta), /path/to/bam ]
    fasta    // channel: [ val(meta), /path/to/fasta ]


    main:
    ch_versions = Channel.empty()


    // Collect all BWAMEM2 output by sample name
    aln
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


    emit:
    bam      = ch_stat                       // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
