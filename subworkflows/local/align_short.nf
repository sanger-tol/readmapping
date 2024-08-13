//
// Align short read (HiC and Illumina) data against the genome
//
params.num_chunks = 4

include { SAMTOOLS_FASTQ    } from '../../modules/nf-core/samtools/fastq/main'
include { BWAMEM2_MEM       } from '../../modules/nf-core/bwamem2/mem/main'
include { SAMTOOLS_MERGE    } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_MERGE as SAMTOOLS_MERGE_CHUNKS } from '../../modules/nf-core/samtools/merge/main' 
include { SAMTOOLS_SORMADUP } from '../../modules/local/samtools_sormadup'
include { SEQKIT_SPLIT2     } from '../../modules/nf-core/seqkit/split2/main'
include { SAMTOOLS_SPLIT    } from '../../modules/local/samtools_split'


workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    index    // channel: [ val(meta), /path/to/bwamem2/ ]
    reads    // channel: [ val(meta), /path/to/datafile ]


    main:
    ch_versions = Channel.empty()

    // Check file types and branch
    reads
    | branch {
        meta, reads ->
            fastq : reads.findAll { it.getName().toLowerCase() =~ /.*f.*\.gz/ }
            cram : true
    }
    | set { ch_reads }


    // Split CRAM files into chunks
    SAMTOOLS_SPLIT ( ch_reads.cram, fasta )
    ch_versions = ch_versions.mix ( SAMTOOLS_SPLIT.out.versions.first() )


    // Assign chunked files to new identifiers
    SAMTOOLS_SPLIT.out.chunked_cram
    | flatMap { meta, chunked_cram -> 
        chunked_cram.collect { 
            def chunk_number = it.getName().toString().split('\\.')[0].split('_')[2..3].join('_')
            def new_meta = meta.clone()
            new_meta.id = "${meta.id}_${chunk_number}"
            [new_meta, it]
        }
    }
    | set { ch_chunks_from_cram }


    // Convert from CRAM to FASTQ only if CRAM files were provided as input
    SAMTOOLS_FASTQ ( ch_chunks_from_cram, false )
    ch_versions = ch_versions.mix ( SAMTOOLS_FASTQ.out.versions.first() )


    // Split FASTQ files into chunks
    SEQKIT_SPLIT2 ( ch_reads.fastq )
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
    | set { ch_chunks_from_fastq }


    // Mix FASTQ files
    ch_chunks_from_fastq
    | mix ( SAMTOOLS_FASTQ.out.fastq )
    | set { ch_reads_fastq }


    // Align Fastq to Genome and output sorted BAM
    BWAMEM2_MEM ( ch_reads_fastq, index, fasta, true )
    ch_versions = ch_versions.mix ( BWAMEM2_MEM.out.versions.first() )


    BWAMEM2_MEM.out.bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..1].join('_'), 'datatype': meta.datatype, 'read_group':meta.read_group, 'read_count': meta.read_count ], bam] }
    | groupTuple( by: [0] )
    | set { ch_bams_merge }


    SAMTOOLS_MERGE_CHUNKS ( ch_bams_merge, [ [], [] ], [ [], [] ] )
    ch_versions = ch_versions.mix ( SAMTOOLS_MERGE_CHUNKS.out.versions.first() )


    // Collect all SAMTOOLS_SORT output by sample name
    SAMTOOLS_MERGE_CHUNKS.out.bam
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

    emit:
    bam      = SAMTOOLS_SORMADUP.out.bam     // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
