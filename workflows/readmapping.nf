
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//

include { INPUT_CHECK                   } from '../subworkflows/local/input_check'
include { SAMTOOLS_COLLATETOFASTQ       } from '../modules/local/samtools_collatetofastq'
include { FASTQC                        } from '../modules/nf-core/fastqc/main'
include { PREPARE_GENOME                } from '../subworkflows/local/prepare_genome'
include { HIC_MAPPING as ALIGN_HIC      } from '../subworkflows/sanger-tol/hic_mapping'
include { ALIGN_SHORT as ALIGN_ILLUMINA } from '../subworkflows/local/align_short'
include { ALIGN_PACBIO as ALIGN_HIFI    } from '../subworkflows/local/align_pacbio'
include { ALIGN_PACBIO as ALIGN_CLR     } from '../subworkflows/local/align_pacbio'
include { ALIGN_ONT                     } from '../subworkflows/local/align_ont'
include { CONVERT_STATS                 } from '../subworkflows/local/convert_stats'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//

include { UNTAR                  } from '../modules/nf-core/untar/main'


include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow READMAPPING {

    take:
    ch_samplesheet
    ch_fasta
    ch_header

    main:
    // Initialize an empty versions channel
    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK ( ch_samplesheet ).reads
    | branch {
        meta, reads ->
            hic : meta.datatype == "hic"
            illumina : meta.datatype == "illumina"
            pacbio : meta.datatype == "pacbio"
            clr : meta.datatype == "pacbio_clr"
            ont : meta.datatype == "ont"
    }
    | set { ch_reads }

    ch_versions = ch_versions.mix ( INPUT_CHECK.out.versions )

    ch_fasta
    | map { [ [ id: it.baseName ], it ] }
    | set { ch_genome }

    PREPARE_GENOME ( ch_genome )
    ch_versions = ch_versions.mix ( PREPARE_GENOME.out.versions )

    //
    // Control quality of input files
    //
    INPUT_CHECK.out.reads
    | branch { meta, reads ->
                cram:  reads.getName().endsWith("cram")
                other: true
    }
    | set { ch_fastqc_reads }

    // Convert cram to FASTQs
    SAMTOOLS_COLLATETOFASTQ ( ch_fastqc_reads.cram, true )

    ch_fastqc_reads = ch_fastqc_reads.other.mix ( SAMTOOLS_COLLATETOFASTQ.out.interleaved )
    FASTQC ( ch_fastqc_reads )

    ch_versions = ch_versions
    | mix ( FASTQC.out.versions )
    | mix ( SAMTOOLS_COLLATETOFASTQ.out.versions )

    //
    // Create channel for vector DB
    //
    // ***PacBio condition does not work - needs fixing***
    if ( ch_reads.pacbio || ch_reads.clr ) {
        if ( params.vector_db.endsWith( '.tar.gz' ) ) {
            UNTAR ( [ [:], params.vector_db ] ).untar
            | set { ch_vector_db }

            ch_versions = ch_versions.mix ( UNTAR.out.versions )

        } else {
            Channel.fromPath ( params.vector_db )
            | set { ch_vector_db }
        }
    }


    //
    // SUBWORKFLOW: Align raw reads to genome
    //
    ALIGN_HIC ( PREPARE_GENOME.out.fasta, ch_reads.hic, params.short_aligner, params.chunk_size, true )
    ch_versions = ch_versions.mix ( ALIGN_HIC.out.versions )

    ALIGN_ILLUMINA ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.bwaidx, ch_reads.illumina )
    ch_versions = ch_versions.mix ( ALIGN_ILLUMINA.out.versions )
    
    ALIGN_HIFI ( PREPARE_GENOME.out.fasta, ch_reads.pacbio, ch_vector_db )
    ch_versions = ch_versions.mix ( ALIGN_HIFI.out.versions )

    ALIGN_CLR ( PREPARE_GENOME.out.fasta, ch_reads.clr, ch_vector_db )
    ch_versions = ch_versions.mix ( ALIGN_CLR.out.versions )

    ALIGN_ONT ( PREPARE_GENOME.out.fasta, ch_reads.ont )
    ch_versions = ch_versions.mix ( ALIGN_ONT.out.versions )

    // gather alignments
    ch_aligned_bams = Channel.empty()
    | mix( ALIGN_HIC.out.bam )
    | mix( ALIGN_ILLUMINA.out.bam )
    | mix( ALIGN_HIFI.out.bam )
    | mix( ALIGN_CLR.out.bam )
    | mix( ALIGN_ONT.out.bam )


    // convert to cram and gather stats
    CONVERT_STATS ( ch_aligned_bams, PREPARE_GENOME.out.fasta, ch_header )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'readmapping_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
