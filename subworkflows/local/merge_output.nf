//
// Merge alignment output files
//

include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'

workflow MERGE_OUTPUT {
    take:
    ch_bam      // channel: [ val(meta), /path/to/bam ]


    main:
    ch_versions = Channel.empty()
    ch_bam = ch_bam.map{ meta, bam -> [ meta + [merged: false], bam ]}

    if ( params.merge_output ) {
        ch_bam
        | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], meta.read_count, bam] }
        | groupTuple( by: [0] )
        | map { meta, read_counts, bams -> [meta + [read_count: read_counts.sum()], bams] }
        | filter { it[1].size() > 1 }
        | set { ch_multi_bams }


        // Merge, but only if there is more than 1 file
        SAMTOOLS_MERGE ( ch_multi_bams, [ [], [] ], [ [], [] ], [ [], [] ] )
        ch_versions = ch_versions.mix ( SAMTOOLS_MERGE.out.versions )


        ch_bam = SAMTOOLS_MERGE.out.bam
        | map { meta, bam -> [meta.tap { it.merged = true }, bam] }
        | mix ( ch_bam )
    }


    emit:
    bam = ch_bam                    // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions          // channel: [ versions.yml ]
}
