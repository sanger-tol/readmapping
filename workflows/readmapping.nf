
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//

include { INPUT_CHECK                        } from '../subworkflows/local/input_check'
include { SAMTOOLS_COLLATETOFASTQ            } from '../modules/local/samtools_collatetofastq'
include { FASTQC                             } from '../modules/nf-core/fastqc'
include { PREPARE_GENOME                     } from '../subworkflows/local/prepare_genome'
include { CRAM_MAP_ILLUMINA_HIC as ALIGN_HIC } from '../subworkflows/sanger-tol/cram_map_illumina_hic'
include { ALIGN_SHORT as ALIGN_ILLUMINA      } from '../subworkflows/local/align_short'
include { ALIGN_PACBIO as ALIGN_HIFI         } from '../subworkflows/local/align_pacbio'
include { ALIGN_PACBIO as ALIGN_CLR          } from '../subworkflows/local/align_pacbio'
include { ALIGN_ONT                          } from '../subworkflows/local/align_ont'
include { CONVERT_STATS                      } from '../subworkflows/local/convert_stats'
include { MULTIQC                            } from '../modules/nf-core/multiqc'
include { MERGE_OUTPUT as HIC_MERGE_SAMPLES  } from '../subworkflows/local/merge_output'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//

include { UNTAR                  } from '../modules/nf-core/untar'


include { paramsSummaryMap                                  } from 'plugin/nf-schema'
include { paramsSummaryMultiqc                              } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML                            } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText                            } from '../subworkflows/local/utils_nfcore_readmapping_pipeline'

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
    ch_versions      = Channel.empty()
    ch_multiqc_files = Channel.empty()
    multiqc_report   = Channel.empty()
    reports          = Channel.empty()

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

    reports = reports.mix ( FASTQC.out.zip )

    ch_versions = ch_versions
    | mix ( FASTQC.out.versions )
    | mix ( SAMTOOLS_COLLATETOFASTQ.out.versions )

    //
    // Create channel for vector DB
    //
    // ***PacBio condition does not work - needs fixing***
    if ( ch_reads.pacbio || ch_reads.clr ) {
        if ( params.hifi_adapter_db.endsWith( '.tar.gz' ) ) {
            UNTAR ( [ [:], params.hifi_adapter_db ] ).untar
            | set { ch_hifi_adapter_db }
            ch_versions = ch_versions.mix ( UNTAR.out.versions )

        } else {
            Channel.fromPath ( params.hifi_adapter_db )
            | set { ch_hifi_adapter_db }
        }
    }

    ch_hifi_adapter_yaml = Channel.fromPath ( params.hifi_adapter_yaml ).collect()
    ch_uli_adapter      = Channel.fromPath ( params.uli_adapter ).collect()

    //
    // SUBWORKFLOW: Align raw reads to genome
    //

    // Prepare fasta channel
    ch_hic = ch_reads.hic
    .combine ( PREPARE_GENOME.out.fasta )
    .multiMap { meta, cram, meta_, fasta ->
        cram: [ meta_ + meta + [ assembly_id: meta_.id ] , cram ]
        fasta: [ meta_ + meta + [ assembly_id: meta_.id ] , fasta ]
    }
    ALIGN_HIC ( ch_hic.fasta, ch_hic.cram, params.short_aligner, params.chunk_size )
    HIC_MERGE_SAMPLES ( ALIGN_HIC.out.bam )
    ch_versions = ch_versions.mix ( ALIGN_HIC.out.versions )
                             .mix ( HIC_MERGE_SAMPLES.out.versions )

    ALIGN_ILLUMINA ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.fasta, ch_reads.illumina )
    ch_versions = ch_versions.mix ( ALIGN_ILLUMINA.out.versions )

    ALIGN_HIFI ( PREPARE_GENOME.out.fasta, ch_reads.pacbio, ch_hifi_adapter_db, ch_hifi_adapter_yaml, ch_uli_adapter )
    ch_versions = ch_versions.mix ( ALIGN_HIFI.out.versions )
    reports = reports.mix ( ALIGN_HIFI.out.post_qc )

    ALIGN_CLR ( PREPARE_GENOME.out.fasta, ch_reads.clr, ch_hifi_adapter_db, ch_hifi_adapter_yaml, ch_uli_adapter )
    ch_versions = ch_versions.mix ( ALIGN_CLR.out.versions )
    reports = reports.mix ( ALIGN_CLR.out.post_qc )

    ALIGN_ONT ( PREPARE_GENOME.out.fasta, ch_reads.ont )
    ch_versions = ch_versions.mix ( ALIGN_ONT.out.versions )

    // gather alignments
    ch_aligned_bams = Channel.empty()
    | mix( HIC_MERGE_SAMPLES.out.bam )
    | mix( ALIGN_ILLUMINA.out.bam )
    | mix( ALIGN_HIFI.out.bam )
    | mix( ALIGN_CLR.out.bam )
    | mix( ALIGN_ONT.out.bam )

    // convert to cram and gather stats
    CONVERT_STATS ( ch_aligned_bams, PREPARE_GENOME.out.fasta, ch_header )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )
    reports = reports.mix ( CONVERT_STATS.out.stats )
                     .mix ( CONVERT_STATS.out.flagstat )
                     .mix ( CONVERT_STATS.out.idxstats )

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
    | collectFile (
            storeDir: "${params.outdir}/pipeline_info",
            name:  'readmapping_software_'  + 'mqc_versions.yml',
            sort: true,
            newLine: true
    )
    | set { ch_collated_versions }

    reports = reports.map { meta, file -> file }

    ch_multiqc_config                     = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config              = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
    ch_multiqc_logo                       = params.multiqc_logo ? Channel.fromPath(params.multiqc_logo, checkIfExists: true) : Channel.empty()
    summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary                   = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files                      = ch_multiqc_files.mix(reports)
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

    MULTIQC (
            ch_multiqc_files.collect(),
            ch_multiqc_config.toList(),
            ch_multiqc_custom_config.toList(),
            ch_multiqc_logo.toList(),
            [],
            []
        )
    multiqc_report = MULTIQC.out.report.toList()


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
