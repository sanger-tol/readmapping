//
// Align Nanopore read files against the genome
//

include { MINIMAP2_ALIGN } from '../../modules/nf-core/minimap2/align/main'
include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_MERGE as SAMTOOLS_MERGE_CHUNKS } from '../../modules/nf-core/samtools/merge/main'
include { SEQKIT_SPLIT2 } from '../../modules/nf-core/seqkit/split2/main'


workflow ALIGN_ONT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    reads    // channel: [ val(meta), /path/to/datafile ]


    main:
    ch_versions = Channel.empty()


    // Split FASTQ files into chunks
    SEQKIT_SPLIT2 ( reads )
    ch_versions = ch_versions.mix ( SEQKIT_SPLIT2.out.versions.first() )


    // Rename reads to include the chunk number, then align individually
    SEQKIT_SPLIT2.out.reads
    | flatMap { meta, reads -> 
        reads.collect { 
            def chunk_number = it.getName().toString().split('\\.')[-3]
            def new_meta = meta.clone()
            new_meta.id = "${meta.id}_${chunk_number}"
            [new_meta, it]
        }
    }
    | set { ch_reads_rg }


    // Align Fastq to Genome with minimap2. bam_format is set to true, making the output a *sorted* BAM
    MINIMAP2_ALIGN ( ch_reads_rg, fasta, true, "bai", false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )


    // Assign chunked BAM files to new identifiers
    MINIMAP2_ALIGN.out.bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..1].join('_'), 'datatype': meta.datatype, 'read_group':meta.read_group, 'read_count': meta.read_count ], bam] }
    | groupTuple( by: [0] )
    | set { ch_bams_merge }


    // Merge chunks
    SAMTOOLS_MERGE_CHUNKS ( ch_bams_merge, [ [], [] ], [ [], [] ] )
    ch_versions = ch_versions.mix ( SAMTOOLS_MERGE_CHUNKS.out.versions.first() )


    // Collect all alignment output by sample name
    SAMTOOLS_MERGE_CHUNKS.out.bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], meta.read_count, bam] }
    | groupTuple ( by: [0] )
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


    // Convert merged BAM to CRAM and calculate indices and statistics
    SAMTOOLS_MERGE.out.bam
    | mix ( ch_bams.single_bam )
    | set { ch_sort }


    emit:
    bam      = ch_sort                       // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
