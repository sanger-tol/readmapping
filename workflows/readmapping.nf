/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def summary_params = NfcoreSchema.paramsSummaryMap(workflow, params)

// Validate input parameters
WorkflowReadmapping.initialise(params, log)

// TODO nf-core: Add all file path parameters for the pipeline to the list below
// Check input path parameters to see if they exist
def checkPathParamList = [ params.input, params.fasta ]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }

// Check mandatory parameters
if (params.input) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet not specified!' }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { INPUT_CHECK                   } from '../subworkflows/local/input_check'
include { PREPARE_GENOME                } from '../subworkflows/local/prepare_genome'
include { ALIGN_SHORT as ALIGN_HIC      } from '../subworkflows/local/align_short'
include { ALIGN_SHORT as ALIGN_ILLUMINA } from '../subworkflows/local/align_short'
include { ALIGN_PACBIO as ALIGN_HIFI    } from '../subworkflows/local/align_pacbio'
include { ALIGN_PACBIO as ALIGN_CLR     } from '../subworkflows/local/align_pacbio'
include { ALIGN_ONT                     } from '../subworkflows/local/align_ont'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { UNTAR                       } from '../modules/nf-core/untar/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/custom/dumpsoftwareversions/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow READMAPPING {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK ( ch_input )
        .reads
        .branch {
            meta, reads ->
                hic : meta.datatype == "hic"
                    return [ meta, reads ]
                illumina : meta.datatype == "illumina"
                    return [ meta, reads ]
                pacbio : meta.datatype == "pacbio"
                    return [ meta, reads ]
                clr : meta.datatype == "pacbio_clr"
                    return [ meta, reads ]
                ont : meta.datatype == "ont"
                    return [ meta, reads ]
        }
        .set { ch_reads }
    ch_versions = ch_versions.mix(INPUT_CHECK.out.versions)

    //
    // SUBWORKFLOW: Uncompress and prepare reference genome files
    //
    PREPARE_GENOME ( ch_fasta )
    ch_versions = ch_versions.mix(PREPARE_GENOME.out.versions)

    //
    // Create channel for vector DB
    //
    if (params.vector_db.endsWith('.tar.gz')) {
        ch_db   = UNTAR ([ [:], params.vector_db ]).untar.map { meta, file -> file }
        ch_versions = ch_versions.mix(UNTAR.out.versions)
    } else {
        ch_db   = file(params.vector_db)
    }

    //
    // SUBWORKFLOW: Align raw reads to genome
    //
    ALIGN_HIC ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.bwaidx, ch_reads.hic)
    ch_versions = ch_versions.mix(ALIGN_HIC.out.versions)

    ALIGN_ILLUMINA ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.bwaidx, ch_reads.illumina )
    ch_versions = ch_versions.mix(ALIGN_ILLUMINA.out.versions)

    ALIGN_HIFI ( PREPARE_GENOME.out.fasta, ch_reads.pacbio, ch_db )
    ch_versions = ch_versions.mix(ALIGN_HIFI.out.versions)

    ALIGN_CLR ( PREPARE_GENOME.out.fasta, ch_reads.clr, ch_db )
    ch_versions = ch_versions.mix(ALIGN_CLR.out.versions)

    ALIGN_ONT ( PREPARE_GENOME.out.fasta, ch_reads.ont )
    ch_versions = ch_versions.mix(ALIGN_ONT.out.versions)

    //
    // MODULE: Combine different versions.yml
    //
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique{ it.text }.collectFile(name: 'collated_versions.yml')
    )

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.IM_notification(workflow, params, summary_params, projectDir, log)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
