//
// Align PacBio read files against the genome
//

include { FILTER_PACBIO                     } from '../../subworkflows/local/filter_pacbio'
include { SAMTOOLS_ADDREPLACERG             } from '../../modules/local/samtools_addreplacerg'
include { SAMTOOLS_INDEX                    } from '../../modules/nf-core/samtools/index/main'
include { GENERATE_CRAM_CSV                 } from '../../modules/local/generate_cram_csv'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM } from '../../modules/local/samtools_sormadup'
include { CREATE_CRAM_FILTER_INPUT          } from '../../subworkflows/local/create_cram_filter_input'
include { MINIMAP2_ALIGN                    } from '../../modules/nf-core/minimap2/align/main'
include { MERGE_OUTPUT                      } from '../../subworkflows/local/merge_output'
include { SAMTOOLS_MERGE                    } from '../../modules/nf-core/samtools/merge/main'

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
    MINIMAP2_ALIGN ( FILTER_PACBIO.out.fastq, fasta, true, "csi", false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )

    MINIMAP2_ALIGN.out.bam
    |map { meta, bam -> [meta.id, meta, bam] }
    |groupTuple()
    |map { id, meta, bam ->
        def newMeta = meta[0].findAll { key, value -> key != 'chunk_id' }
        [newMeta, bam]
    }
    |set { collected_files_for_merge }


    // Merge chunked aligned bams from minimap align
    SAMTOOLS_MERGE (
        collected_files_for_merge,
        fasta,
        [ [], [] ],
        [ [], [] ]
    )

    //
    // SUBWORKFLOW: Merge all alignment output by sample name
    //
    ch_sort  = MERGE_OUTPUT( SAMTOOLS_MERGE.out.bam ).bam
    ch_versions = ch_versions.mix ( MERGE_OUTPUT.out.versions)

    emit:
    bam      = ch_sort                       // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
