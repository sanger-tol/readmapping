//
// Subworkflow with functionality specific to the sanger-tol/readmapping pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFVALIDATION_PLUGIN } from '../../nf-core/utils_nfvalidation_plugin'
include { paramsSummaryMap          } from 'plugin/nf-validation'
include { fromSamplesheet           } from 'plugin/nf-validation'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { logColours                } from '../../nf-core/utils_nfcore_pipeline'
include { getWorkflowVersion        } from '../../nf-core/utils_nfcore_pipeline'
include { dashedLine                } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { workflowCitation          } from '../../nf-core/utils_nfcore_pipeline'

/*
========================================================================================
    SUBWORKFLOW TO INITIALISE PIPELINE
========================================================================================
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    help              // boolean: Display help text
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir
    input

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    pre_help_text = sangerTolLogo(monochrome_logs)
    post_help_text = '\n' + workflowCitation() + '\n' + dashedLine(monochrome_logs)
    def String workflow_command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"
    UTILS_NFVALIDATION_PLUGIN (
        help,
        workflow_command,
        pre_help_text,
        post_help_text,
        validate_params,
        "nextflow_schema.json"
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    // Check input path parameters to see if they exist
    def checkPathParamList = [
        params.input,
        params.fasta,
        params.vector_db,
        params.bwamem2_index
    ]

    for (param in checkPathParamList) {
        if (param) { file(param, checkIfExists: true) }
    }

    // Create channels from input paths
    ch_fasta = params.fasta ? Channel.fromPath(params.fasta) : Channel.empty().tap { error 'Genome fasta file not specified!' }
    ch_header = params.header ? Channel.fromPath(params.header) : Channel.empty()


    //
    // Create channel from input samplesheet
    //
    Channel
        .fromSamplesheet("input")
        .map { row ->
            def meta = row[0] + [id: file(row[0].datafile).baseName]
            return [meta, file(row[0].datafile, checkIfExists: true)]
        }
        .set { ch_samplesheet }
    validateInputSamplesheet(ch_samplesheet)
        .set { ch_validated_samplesheet }

    emit:
    samplesheet = ch_validated_samplesheet
    fasta       = ch_fasta
    header      = ch_header
    versions    = ch_versions
}

/*
========================================================================================
    SUBWORKFLOW FOR PIPELINE COMPLETION
========================================================================================
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:

    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(summary_params, email, email_on_fail, plaintext_email, outdir, monochrome_logs, multiqc_report.toList())
        }

        completionSummary(monochrome_logs)

        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
========================================================================================
    FUNCTIONS
========================================================================================
*/


//
// Check and validate pipeline parameters
//
def validateInputParameters() {
    // Validate fasta parameter
    if (!params.fasta) {
        log.error "Genome fasta file not specified with e.g. '--fasta genome.fa' or via a detectable config file."
    }

    // Validate outfmt parameter
    if (!params.outfmt) {
        log.error "Output format not specified. Please specify '--outfmt bam', '--outfmt cram', or both separated by a comma."
    } else {
        def outfmtOptions = params.outfmt.split(',').collect { it.trim() }
        def validOutfmtOptions = ['bam', 'cram']
        def invalidOptions = outfmtOptions.findAll { !(it in validOutfmtOptions) }

        if (invalidOptions) {
            log.error "Invalid output format(s) specified: '${invalidOptions.join(', ')}'. Valid options are 'bam' or 'cram'."
        }
    }
    // Validate compression parameter
    if (!params.compression) {
        log.error "Compression option not specified. Please specify '--compression none' or '--compression crumble'."
    } else if (!(params.compression in ['none', 'crumble'])) {
        log.error "Invalid compression option specified: '${params.compression}'. Valid options are 'none' or 'crumble'."
    }
}

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(channel) {
    def seen = [:].withDefault { 0 }
    def uniquePairs = new HashSet()
    def validFormats = [".fq.gz", ".fastq.gz", ".cram", ".bam"]

    return channel.map { sample ->
        def (meta, file) = sample

        // Replace spaces with underscores in sample names
        meta.sample = meta.sample.replace(" ", "_")

        // Validate that the file path is non-empty and has a valid format
        if (!file || !validFormats.any { file.toString().endsWith(it) }) {
            error("Data file is required and must have a valid extension: ${file}")
        }

        def pair = [meta.sample, file.toString()].toString()

        if (!uniquePairs.add(pair)) {
            error("The pair of sample name and read file must be unique: ${pair}")
        }

        seen[meta.sample] += 1
        meta.sample = "${meta.sample}_T${seen[meta.sample]}"

        return [meta, file]
    }
}

//
// Sanger-ToL logo
//
def sangerTolLogo(monochrome_logs=true) {
    Map colors = logColours(monochrome_logs)
    String.format(
        """\n
        ${dashedLine(monochrome_logs)}
        ${colors.blue}   _____                               ${colors.green} _______   ${colors.red} _${colors.reset}
        ${colors.blue}  / ____|                              ${colors.green}|__   __|  ${colors.red}| |${colors.reset}
        ${colors.blue} | (___   __ _ _ __   __ _  ___ _ __ ${colors.reset} ___ ${colors.green}| |${colors.yellow} ___ ${colors.red}| |${colors.reset}
        ${colors.blue}  \\___ \\ / _` | '_ \\ / _` |/ _ \\ '__|${colors.reset}|___|${colors.green}| |${colors.yellow}/ _ \\${colors.red}| |${colors.reset}
        ${colors.blue}  ____) | (_| | | | | (_| |  __/ |        ${colors.green}| |${colors.yellow} (_) ${colors.red}| |____${colors.reset}
        ${colors.blue} |_____/ \\__,_|_| |_|\\__, |\\___|_|        ${colors.green}|_|${colors.yellow}\\___/${colors.red}|______|${colors.reset}
        ${colors.blue}                      __/ |${colors.reset}
        ${colors.blue}                     |___/${colors.reset}
        ${colors.purple}  ${workflow.manifest.name} ${getWorkflowVersion()}${colors.reset}
        ${dashedLine(monochrome_logs)}
        """.stripIndent()
    )
}


//
// Generate methods description for tools
//
def toolCitationText() {
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "Tool (Foo et al. 2023)" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def citation_text = [
            "Tools used in the workflow included:",
            "BBtools (Buschnell 2014),",
            "blastn (Camacho et al. 2009),",
            "bwa-mem2 (Vasimuddin et al. 2019),",
            "Crumble (Bonfield et al. 2019),",
            "MiniMap2 (Li 2018),",
            "Samtools (Li et al. 2009)"
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    // Can use ternary operators to dynamically construct based conditions, e.g. params["run_xyz"] ? "<li>Author (2023) Pub name, Journal, DOI</li>" : "",
    // Uncomment function in methodsDescriptionText to render in MultiQC report
    def reference_text = [
            "<li>Buschnell, B. (2014). BBtools software package. sourceforge.net/projects/bbmap.</li>",
            "<li>Camacho, C., Coulouris, G., Avagyan, V., Ma, N., Papadopoulos, J., Bealer, K., & Madden, T.L. (2009). BLAST+: architecture and applications. BMC Bioinformatics, 10, 421. doi:10.1186/1471-2105-10-421.</li>",
            "<li>Vasimuddin, Md., Misra, S., Li, H., & Aluru, S. (2019). Efficient Architecture-Aware Acceleration of BWA-MEM for Multicore Systems. IEEE Parallel and Distributed Processing Symposium (IPDPS), 2019. doi:10.1109/IPDPS.2019.00041.</li>",
            "<li>Bonfield, J.K., McCarthy, S.A., & Durbin, R. (2019). Crumble: reference free lossy compression of sequence quality values. Bioinformatics, 35(2), 337-339. doi:10.1093/bioinformatics/bty608.</li>",
            "<li>Li, H. (2018). Minimap2: pairwise alignment for nucleotide sequences. Bioinformatics, 34(18), 3094-3100. doi:10.1093/bioinformatics/bty191.</li>",
            "<li>Li, H., Handsaker, B., Wysoker, A., Fennell, T., Ruan, J., Homer, N., ... & Durbin, R. (2009). The Sequence Alignment/Map format and SAMtools. Bioinformatics, 25(16), 2078-2079. doi:10.1093/bioinformatics/btp352.</li>"
        ].join(' ').trim()

    return reference_text
}
def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        String[] manifest_doi = meta.manifest_map.doi.tokenize(",")
        for (String doi_ref: manifest_doi) temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
