//
// Align short read (HiC and Illumina) data against the genome
//

include { SAMTOOLS_SORMADUP                 } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_INDEX                    } from '../../modules/nf-core/samtools/index/main'
include { GENERATE_CRAM_CSV                 } from '../../modules/local/generate_cram_csv'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_ADDREPLACERG             } from '../../modules/local/samtools_addreplacerg'
include { MINIMAP2_MAPREDUCE                } from '../../subworkflows/local/minimap2_mapreduce'
include { BWAMEM2_MAPREDUCE                 } from '../../subworkflows/local/bwamem2_mapreduce'
include { MERGE_OUTPUT                      } from '../../subworkflows/local/merge_output'

workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ] reference_tuple
    index    // channel: [ val(meta), /path/to/bwamem2/ ]
    reads    // channel: [ val(meta), /path/to/datafile ] hic_reads_path


    main:
    ch_versions = Channel.empty()
    ch_merged_bam   = Channel.empty()

    // Check file types and branch
    reads
    | branch {
        meta, reads ->
            fastq : reads.findAll { it.getName().toLowerCase() =~ /.*f.*\.gz/ }
            cram : true
    }
    | set { ch_reads }


    // Convert FASTQ to CRAM only if FASTQ were provided as input
    CONVERT_CRAM ( ch_reads.fastq, fasta )
    ch_versions = ch_versions.mix ( CONVERT_CRAM.out.versions )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    | mix ( ch_reads.cram )
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
    if (params.short_aligner.startsWith("minimap")) {
        MINIMAP2_MAPREDUCE (
            fasta,
            GENERATE_CRAM_CSV.out.csv
        )
        ch_versions         = ch_versions.mix( MINIMAP2_MAPREDUCE.out.versions )
        ch_merged_bam           = ch_merged_bam.mix(MINIMAP2_MAPREDUCE.out.mergedbam)
    } else {
        BWAMEM2_MAPREDUCE (
            fasta,
            GENERATE_CRAM_CSV.out.csv,
            index
        )
        ch_versions         = ch_versions.mix( BWAMEM2_MAPREDUCE.out.versions )
        ch_merged_bam       = ch_merged_bam.mix(BWAMEM2_MAPREDUCE.out.mergedbam)
    }

    ch_merged_bam
    | combine( ch_reads_cram_crai )
    | filter { meta_bam, bam, meta_cram, cram, crai -> meta_bam.id == meta_cram.id }
    | map { meta_bam, bam, meta_cram, cram, crai -> [ meta_cram, bam ] }
    | set { ch_merged_bam }

    //
    // SUBWORKFLOW: Merge all alignment output by sample name
    //
    ch_sort = MERGE_OUTPUT( ch_merged_bam ).bam
    ch_versions = ch_versions.mix ( MERGE_OUTPUT.out.versions)

    // Mark duplicates
    SAMTOOLS_SORMADUP ( ch_sort, fasta )
    ch_versions = ch_versions.mix ( SAMTOOLS_SORMADUP.out.versions )


    emit:
    bam      = SAMTOOLS_SORMADUP.out.bam     // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
