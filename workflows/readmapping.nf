
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { ALIGN_SHORT                        } from '../subworkflows/local/align_short'
include { ALIGN_LONG                         } from '../subworkflows/local/align_long'
include { CONVERT_STATS                      } from '../subworkflows/local/convert_stats'
include { INPUT_CHECK                        } from '../subworkflows/local/input_check'


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//

include { FASTQC         } from '../modules/nf-core/fastqc'
include { MULTIQC        } from '../modules/nf-core/multiqc'

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

    // Initialize input values for PacBio read preprocessing
    val_pacbio_adapter = params.pacbio_adapter ?: []
    val_pacbio_adapter_yaml = params.pacbio_adapter_yaml ?: []
    val_pacbio_uli_adapter  = params.pacbio_uli_adapter ?: []

    //
    // SUBWORKFLOW: Prepare the reads and the genome
    //
    ch_genome = ch_fasta.map { fasta -> [[id: fasta.baseName], fasta] }

    INPUT_CHECK(ch_genome, ch_samplesheet)
    ch_reads = INPUT_CHECK.out.reads.branch {
        meta, _reads ->
            short_reads : meta.datatype == "hic" || meta.datatype == "illumina"
            long_reads : true
    }

    //
    // Control quality of input files
    //

    FASTQC ( INPUT_CHECK.out.reads )
    reports = reports.mix ( FASTQC.out.zip )

    //
    // SUBWORKFLOW: Align raw reads to genome
    //

    ALIGN_SHORT ( INPUT_CHECK.out.fasta, ch_reads.short_reads )

    ALIGN_LONG (
        INPUT_CHECK.out.fasta,
        ch_reads.long_reads,
        val_pacbio_adapter,
        val_pacbio_adapter_yaml,
        val_pacbio_uli_adapter,
    )

    reports = reports.mix ( ALIGN_LONG.out.mqc_files )

    // gather alignments
    ch_aligned_bams = channel.empty()
    .mix( ALIGN_SHORT.out.bam )
    .mix( ALIGN_LONG.out.bam )

    // convert to cram and gather stats
    CONVERT_STATS ( ch_aligned_bams, INPUT_CHECK.out.fasta, ch_header )
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

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'readmapping_software_mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //

    def collated_reports = channel.topic("multiqc_files")
        .map { _meta, _process, _tool, reports_ -> reports_ }

    // MULTIQC
    def ch_datatype_reports = reports
        .map { meta, file -> [ meta.datatype ?: 'unknown', file ] }
        .groupTuple(by: 0)
        .map { datatype, files -> [ [id: "readmapping_${datatype}", datatype: datatype], files.unique() ] }

    def ch_all_reports = reports
        .map { _meta, file -> file }
        .collect()
        .map { files -> [ [id: 'readmapping_overall', datatype: 'all'], files.unique() ] }

    def summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def workflow_summary = channel.value(paramsSummaryMultiqc(summary_params))
    def multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def methods_description = channel.value(methodsDescriptionText(multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(collated_reports)
    ch_multiqc_files = ch_multiqc_files.mix(workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

    def ch_multiqc_global_files = ch_multiqc_files.flatten().collect()

    def ch_multiqc_reports = ch_datatype_reports
        .mix(ch_all_reports)

    MULTIQC(
        ch_multiqc_reports.combine(ch_multiqc_global_files).map { row ->
            def meta = row[0]
            def report_files = row[1]
            def global_files = row.size() > 2 ? row[2..-1] : []
            [
                meta,
                (report_files + global_files).unique(),
                params.multiqc_config
                    ? file(params.multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                params.multiqc_logo ? file(params.multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    multiqc_report  = MULTIQC.out.report
        .map { _meta, report -> [report] }
        .toList() // channel: list of /path/to/multiqc reports (overall + per datatype)
    multiqc_publish = MULTIQC.out.data.mix(MULTIQC.out.plots, MULTIQC.out.report)
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
