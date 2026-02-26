//
// Merge alignment output files
//

include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'

workflow MERGE_OUTPUT {
    take:
    ch_bam      // channel: [ val(meta), /path/to/bam ]


    main:
    ch_bam = ch_bam.map{ meta, bam -> [ meta + [merged: false], bam ]}

    if ( params.merge_output ) {
        ch_multi_bams = ch_bam
        .map { meta, bam -> [['specimen':meta.specimen, 'datatype': meta.datatype], meta.run_accession, meta.read_count, bam] }
        .groupTuple( by: [0] )
        .map { meta, run_accessions, read_counts, bams -> [meta + [id: run_accessions.sort().join("."), merge_source: run_accessions.sort().join("\n"), read_count: read_counts.sum()], bams] }
        .filter { _meta, bams -> bams.size() > 1 }
        .map { meta, bam -> [meta + [merged: true], bam] }

        // Merge, but only if there is more than 1 file
        SAMTOOLS_MERGE ( ch_multi_bams, [ [], [] ], [ [], [] ], [ [], [] ] )

        ch_bam = SAMTOOLS_MERGE.out.bam
        .mix ( ch_bam )
    }

    emit:
    bam = ch_bam                    // channel: [ val(meta), /path/to/bam ]
}
