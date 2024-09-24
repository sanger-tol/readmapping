//
// Align Nanopore read files against the genome
//

include { SAMTOOLS_ADDREPLACERG } from '../../modules/local/samtools_addreplacerg'
include { SAMTOOLS_INDEX } from '../../modules/nf-core/samtools/index/main'
include { GENERATE_CRAM_CSV } from '../../modules/local/generate_cram_csv'
include { MINIMAP2_MAPREDUCE } from '../../subworkflows/local/minimap2_mapreduce'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'


workflow ALIGN_ONT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    reads    // channel: [ val(meta), /path/to/datafile ]


    main:
    ch_versions = Channel.empty()
    ch_merged_bam   = Channel.empty()

    // Convert FASTQ to CRAM
    CONVERT_CRAM ( reads, fasta )
    ch_versions = ch_versions.mix ( CONVERT_CRAM.out.versions )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    | set { ch_reads_cram }

    // Index the CRAM file
    SAMTOOLS_INDEX ( ch_reads_cram )
    ch_versions = ch_versions.mix( SAMTOOLS_INDEX.out.versions )

    ch_reads_cram
    | join ( SAMTOOLS_INDEX.out.crai )
    | set { ch_reads_cram_crai }


    //
    // MODULE: generate a CRAM CSV file containing the required parametres for CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT
    //
    GENERATE_CRAM_CSV( ch_reads_cram_crai )
    ch_versions = ch_versions.mix( GENERATE_CRAM_CSV.out.versions )

    //
    // SUBWORKFLOW: mapping hic reads using minimap2 or bwamem2
    //
    MINIMAP2_MAPREDUCE (
        fasta,
        GENERATE_CRAM_CSV.out.csv
    )
    ch_versions         = ch_versions.mix( MINIMAP2_MAPREDUCE.out.versions )
    ch_merged_bam           = ch_merged_bam.mix(MINIMAP2_MAPREDUCE.out.mergedbam)


    ch_merged_bam
    | combine( ch_reads_cram_crai )
    | map { meta_bam, bam, meta_cram, cram, crai -> [ meta_cram, bam ] }
    | set { ch_merged_bam }


    // Collect all BAM output by sample name
    ch_merged_bam
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


    // Convert merged BAM to CRAM and calculate indices and statistics
    SAMTOOLS_MERGE.out.bam
    | mix ( ch_bams.single_bam )
    | set { ch_sort }


    emit:
    bam      = ch_sort                       // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
