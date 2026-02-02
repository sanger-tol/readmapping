
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
include { ALIGN_SHORT                        } from '../subworkflows/local/align_short'
include { ALIGN_PACBIO as ALIGN_HIFI         } from '../subworkflows/local/align_pacbio'
include { ALIGN_PACBIO as ALIGN_CLR          } from '../subworkflows/local/align_pacbio'
include { ALIGN_ONT                          } from '../subworkflows/local/align_ont'
include { CONVERT_STATS                      } from '../subworkflows/local/convert_stats'
include { MULTIQC                            } from '../modules/nf-core/multiqc'
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
    ch_versions      = channel.empty()
    ch_multiqc_files = channel.empty()
    multiqc_report   = channel.empty()
    reports          = channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK ( ch_samplesheet ).reads
    .branch {
        meta, _reads ->
            short_ : meta.datatype == "hic" || meta.datatype == "illumina"
            pacbio : meta.datatype == "pacbio"
            clr : meta.datatype == "pacbio_clr"
            ont : meta.datatype == "ont"
    }
    .set { ch_reads }

    ch_versions = ch_versions.mix ( INPUT_CHECK.out.versions )

    ch_fasta
    .map { fasta -> [ [ id: fasta.baseName ], fasta ] }
    .set { ch_genome }

    PREPARE_GENOME ( ch_genome )
    ch_versions = ch_versions.mix ( PREPARE_GENOME.out.versions )

    //
    // Control quality of input files
    //
    INPUT_CHECK.out.reads
    .branch { _meta, reads ->
                cram:  reads.getName().endsWith("cram")
                other: true
    }
    .set { ch_fastqc_reads }

    // Convert cram to FASTQs
    SAMTOOLS_COLLATETOFASTQ ( ch_fastqc_reads.cram, true )

    ch_fastqc_reads = ch_fastqc_reads.other.mix ( SAMTOOLS_COLLATETOFASTQ.out.interleaved )
    FASTQC ( ch_fastqc_reads )

    reports = reports.mix ( FASTQC.out.zip )

    ch_versions = ch_versions
    .mix ( SAMTOOLS_COLLATETOFASTQ.out.versions )

    //
    // Create channel for vector DB
    //
    // ***PacBio condition does not work - needs fixing***
    if ( ch_reads.pacbio || ch_reads.clr ) {
        if ( params.hifi_adapter_db.endsWith( '.tar.gz' ) ) {
            UNTAR ( [ [:], params.hifi_adapter_db ] ).untar
            .set { ch_hifi_adapter_db }
            ch_versions = ch_versions.mix ( UNTAR.out.versions )

        } else {
            channel.fromPath ( params.hifi_adapter_db )
            .set { ch_hifi_adapter_db }
        }
    }

    ch_hifi_adapter_yaml = channel.fromPath ( params.hifi_adapter_yaml ).collect()
    ch_uli_adapter      = channel.fromPath ( params.uli_adapter ).collect()

    //
    // SUBWORKFLOW: Align raw reads to genome
    //

    ALIGN_SHORT ( PREPARE_GENOME.out.fasta, ch_reads.short_ )
    ch_versions = ch_versions.mix ( ALIGN_SHORT.out.versions )

    ALIGN_HIFI ( PREPARE_GENOME.out.fasta, ch_reads.pacbio, ch_hifi_adapter_db, ch_hifi_adapter_yaml, ch_uli_adapter )
    ch_versions = ch_versions.mix ( ALIGN_HIFI.out.versions )
    reports = reports.mix ( ALIGN_HIFI.out.post_qc )

    ALIGN_CLR ( PREPARE_GENOME.out.fasta, ch_reads.clr, ch_hifi_adapter_db, ch_hifi_adapter_yaml, ch_uli_adapter )
    ch_versions = ch_versions.mix ( ALIGN_CLR.out.versions )
    reports = reports.mix ( ALIGN_CLR.out.post_qc )

    ALIGN_ONT ( PREPARE_GENOME.out.fasta, ch_reads.ont )
    ch_versions = ch_versions.mix ( ALIGN_ONT.out.versions )

    // gather alignments
    ch_aligned_bams = channel.empty()
    .mix( ALIGN_SHORT.out.bam )
    .mix( ALIGN_HIFI.out.bam )
    .mix( ALIGN_CLR.out.bam )
    .mix( ALIGN_ONT.out.bam )

    // convert to cram and gather stats
    CONVERT_STATS ( ch_aligned_bams, PREPARE_GENOME.out.fasta, ch_header )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )
    reports = reports.mix ( CONVERT_STATS.out.stats )
                     .mix ( CONVERT_STATS.out.flagstat )
                     .mix ( CONVERT_STATS.out.idxstats )

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'readmapping_software_mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    reports = reports.map { _meta, file -> file }

    ch_multiqc_config                     = channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config              = params.multiqc_config ? channel.fromPath(params.multiqc_config, checkIfExists: true) : channel.empty()
    ch_multiqc_logo                       = params.multiqc_logo ? channel.fromPath(params.multiqc_logo, checkIfExists: true) : channel.empty()
    summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary                   = channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
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
    versions       = ch_collated_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
