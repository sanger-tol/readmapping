//
// Align PacBio read files against the genome
//

// Include local modules and subworkflows
include { PACBIO_PBMARKDUP                  } from '../../modules/local/pbmarkdup'
include { GENERATE_CRAM_CSV                 } from '../../modules/local/generate_cram_csv'
include { HIFI_TRIMMER                      } from '../../modules/local/hifi_trimmer'
include { SAMTOOLS_COLLATETOFASTA           } from '../../modules/local/samtools_collatetofasta'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_ADDREPLACERG             } from '../../modules/local/samtools_addreplacerg'

include { CREATE_CRAM_FILTER_INPUT          } from '../../subworkflows/local/create_cram_filter_input'
include { MERGE_OUTPUT                      } from '../../subworkflows/local/merge_output'

// Include nf-core modules
include { BLAST_BLASTN as BLASTN_HIFI       } from '../../modules/nf-core/blast/blastn/main'
include { LIMA                              } from '../../modules/nf-core/lima'
include { SAMTOOLS_INDEX                    } from '../../modules/nf-core/samtools/index'
include { FASTQC as FASTQC_FILTERED         } from '../../modules/nf-core/fastqc'
include { MINIMAP2_ALIGN                    } from '../../modules/nf-core/minimap2/align'
include { SAMTOOLS_MERGE                    } from '../../modules/nf-core/samtools/merge'
include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_FASTQ                    } from '../../modules/nf-core/samtools/fastq/main'
include { TABIX_BGZIP as BGZIP_BLASTN       } from '../../modules/nf-core/tabix/bgzip/main'

workflow ALIGN_PACBIO {
    take:
    fasta               // channel: [ val(meta), /path/to/fasta ]
    reads               // channel: [ val(meta), /path/to/datafile ]
    hifi_adapter_db     // channel: /path/to/hifi_adapter_db
    hifi_adapter_yaml   // channel: /path/to/hifi_adapter_yaml
    uli_adapter         // channel: /path/to/uli_adapter.fasta


    main:
    ch_versions    = Channel.empty()
    ch_merged_bam  = Channel.empty()
    ch_post_qc     = Channel.empty()

    // Branch for handling ultra low-input libraries
    reads
    | branch {
        meta, reads ->
            uli : meta.library == "uli"
            other : true
    }
    | set { ch_reads_branched }

    // Trim ULI adapter
    bam_for_md = ch_reads_branched.uli
    if ( params.trim_uli_adapter ) {
        bam_for_md = LIMA ( ch_reads_branched.uli, uli_adapter ).bam
        ch_versions = ch_versions.mix ( LIMA.out.versions.first() )
    }

    // Mark/remove duplicates
    PACBIO_PBMARKDUP ( bam_for_md )
    ch_versions = ch_versions.mix ( PACBIO_PBMARKDUP.out.versions.first() )

    PACBIO_PBMARKDUP.out.output
    | mix ( ch_reads_branched.other )
    | set { ch_reads_all }

    // Convert input to CRAM
    CONVERT_CRAM ( ch_reads_all, fasta )
    ch_versions = ch_versions.mix ( CONVERT_CRAM.out.versions )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    // Index the CRAM file
    SAMTOOLS_INDEX ( SAMTOOLS_ADDREPLACERG.out.cram )
    ch_versions = ch_versions.mix( SAMTOOLS_INDEX.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    | join ( SAMTOOLS_INDEX.out.crai )
    | set { ch_reads_cram }

    GENERATE_CRAM_CSV ( ch_reads_cram )
    ch_versions = ch_versions.mix ( GENERATE_CRAM_CSV.out.versions )

    CREATE_CRAM_FILTER_INPUT ( GENERATE_CRAM_CSV.out.csv, fasta )
    ch_versions = ch_versions.mix ( CREATE_CRAM_FILTER_INPUT.out.versions )

    //
    // FILTER BAMs AND OUTPUT AS FASTQ
    //
    CREATE_CRAM_FILTER_INPUT.out.chunked_cram
    | map { meta, cram -> [ meta, cram, [] ] }
    | set { ch_pacbio }

    SAMTOOLS_CONVERT ( ch_pacbio, [ [], [] ], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_CONVERT.out.versions )

    if ( params.filter_pacbio ) {
        // Collate BAM file to create interleaved FASTA
        SAMTOOLS_COLLATETOFASTA ( SAMTOOLS_CONVERT.out.bam )
        ch_versions = ch_versions.mix ( SAMTOOLS_COLLATETOFASTA.out.versions )

        BLASTN_HIFI ( SAMTOOLS_COLLATETOFASTA.out.fasta, hifi_adapter_db )
        ch_versions = ch_versions.mix ( BLASTN_HIFI.out.versions )

        BGZIP_BLASTN ( BLASTN_HIFI.out.txt )
        ch_versions = ch_versions.mix ( BGZIP_BLASTN.out.versions )

        bam_blast = SAMTOOLS_CONVERT.out.bam.join ( BGZIP_BLASTN.out.output )

        HIFI_TRIMMER ( bam_blast, hifi_adapter_yaml )
        ch_versions = ch_versions.mix ( HIFI_TRIMMER.out.versions )

        ch_reads_for_align =  HIFI_TRIMMER.out.fastq

        // FastQC on filtered reads
        FASTQC_FILTERED ( ch_reads_for_align )
        ch_versions = ch_versions.mix ( FASTQC_FILTERED.out.versions )
        ch_post_qc = ch_post_qc.mix ( FASTQC_FILTERED.out.zip )
    } else {
        SAMTOOLS_FASTQ ( SAMTOOLS_CONVERT.out.bam, false )
        ch_versions = ch_versions.mix ( SAMTOOLS_FASTQ.out.versions )
        ch_reads_for_align = SAMTOOLS_FASTQ.out.other
    }

    // Align without map reduce
    // Align Fastq to Genome with minimap2. bam_format is set to true, making the output a *sorted* BAM
    MINIMAP2_ALIGN ( ch_reads_for_align, fasta, true, "csi", false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )

    MINIMAP2_ALIGN.out.bam
    | map { meta, file -> [meta.id, meta, file] }
    | groupTuple()
    | map { id, metas, files -> [ metas[0] - [chunk_id: metas[0].chunk_id], files ] }
    | set { collected_files_for_merge }

    //
    // MODULE: Merge chunked aligned bams
    //
    SAMTOOLS_MERGE (
        collected_files_for_merge,
        fasta,
        [ [], [] ],
        [ [], [] ]
    )

    //
    // SUBWORKFLOW: Merge all alignment output by sample name
    //
    ch_sort  = MERGE_OUTPUT ( SAMTOOLS_MERGE.out.bam ).bam
    ch_versions = ch_versions.mix ( MERGE_OUTPUT.out.versions )


    emit:
    bam      = ch_sort                       // channel: [ val(meta), /path/to/bam ]
    post_qc  = ch_post_qc                    // channel: [ val(meta), /path/to/fastqc zip]
    versions = ch_versions                   // channel: [ versions.yml ]
}
