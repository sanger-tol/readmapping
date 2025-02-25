//
// Align short read (HiC and Illumina) data against the genome
//

include { SAMTOOLS_COLLATETOFASTQ } from '../../modules/local/samtools_collatetofastq'
include { BWAMEM2_MEM             } from '../../modules/nf-core/bwamem2/mem/main'
include { SAMTOOLS_MERGE          } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORMADUP       } from '../../modules/local/samtools_sormadup'


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


    // Convert from CRAM to FASTQ only if CRAM files were provided as input
    SAMTOOLS_COLLATETOFASTQ ( ch_reads.cram, true )
    ch_versions = ch_versions.mix ( SAMTOOLS_COLLATETOFASTQ.out.versions.first() )


    SAMTOOLS_COLLATETOFASTQ.out.interleaved
    | mix ( ch_reads.fastq )
    | set { ch_reads_fastq }


    // Align Fastq to Genome and output sorted BAM
    BWAMEM2_MEM ( ch_reads_fastq, index, fasta, true )
    ch_versions = ch_versions.mix ( BWAMEM2_MEM.out.versions.first() )


    // Collect all BWAMEM2 output by sample name
    BWAMEM2_MEM.out.bam
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
