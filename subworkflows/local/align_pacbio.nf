//
// Align PacBio read files against the genome
//

include { FILTER_PACBIO  } from '../../subworkflows/local/filter_pacbio'
include { SAMTOOLS_ADDREPLACERG } from '../../modules/local/samtools_addreplacerg'
include { SAMTOOLS_INDEX } from '../../modules/nf-core/samtools/index/main'
include { GENERATE_CRAM_CSV } from '../../modules/local/generate_cram_csv'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'
include { CREATE_CRAM_FILTER_INPUT } from '../../subworkflows/local/create_cram_filter_input'
include { MINIMAP2_ALIGN } from '../../modules/nf-core/minimap2/align/main'

workflow ALIGN_PACBIO {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db


    main:
    ch_versions = Channel.empty()
    ch_merged_bam   = Channel.empty()

    // Convert input to CRAM
    CONVERT_CRAM ( reads, fasta )
    ch_versions = ch_versions.mix ( CONVERT_CRAM.out.versions )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    // Index the CRAM file
    SAMTOOLS_INDEX ( SAMTOOLS_ADDREPLACERG.out.cram )
    ch_versions = ch_versions.mix( SAMTOOLS_INDEX.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    | join ( SAMTOOLS_INDEX.out.crai )
    | set { ch_reads_cram }

    GENERATE_CRAM_CSV( ch_reads_cram )
    ch_versions = ch_versions.mix( GENERATE_CRAM_CSV.out.versions )

    CREATE_CRAM_FILTER_INPUT ( GENERATE_CRAM_CSV.out.csv, fasta )
    ch_versions = ch_versions.mix( CREATE_CRAM_FILTER_INPUT.out.versions )

    // Filter BAM and output as FASTQ
    FILTER_PACBIO ( CREATE_CRAM_FILTER_INPUT.out.chunked_cram, db )
    ch_versions = ch_versions.mix ( FILTER_PACBIO.out.versions )

    // Align without map reduce
    // Align Fastq to Genome with minimap2. bam_format is set to true, making the output a *sorted* BAM
    MINIMAP2_ALIGN ( FILTER_PACBIO.out.fastq, fasta, true, "bai", false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )

    // Collect all alignment output by sample name
    MINIMAP2_ALIGN.out.bam
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
