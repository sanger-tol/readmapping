//
// Check input samplesheet and get read channels
//
include { INPUT_TOL         } from '../../modules/local/input_tol'
include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'

workflow INPUT_CHECK {
    take:
    inputs     // either [ file(params.input), file(params.fasta) ] or [ params.input, params.project ]

    main:
    ch_versions = Channel.empty()

    // If ToL ID and project is used create samplesheet and uncompress genome
    inputs.multiMap { in1, in2 ->
        input : in1
        proj  : in2
    }
    .set{ch_input}

    if (params.input && params.fasta) {
        samplesheet = ch_input.input
        genome      = ch_input.proj
        tol         = 0
    } else if (params.input && params.project) {
        INPUT_TOL (ch_input.input, ch_input.proj)
        samplesheet = INPUT_TOL.out.csv
        genome      = INPUT_TOL.out.fasta
        tol         = 1
        ch_versions = ch_versions.mix(INPUT_TOL.out.versions)
    }

    SAMPLESHEET_CHECK ( samplesheet )
        .csv
        .splitCsv ( header:true, sep:',' )
        .map { create_data_channels( it, tol ) }
        .set { reads }
    ch_versions = ch_versions.mix(SAMPLESHEET_CHECK.out.versions)

    emit:
    reads                                     // channel: [ val(meta), [ reads ] ]
    genome                                    // channel: /path/to/fasta
    versions = SAMPLESHEET_CHECK.out.versions // channel: [ versions.yml ]
}

// Function to get list of [ meta, [ datafile ] ]
def create_data_channels(LinkedHashMap row, tol) {
    def meta = [:]
    meta.id         = row.sample
    meta.datatype   = row.datatype
    meta.library    = (row.library == "") ? row.datafile.split('/')[-1].split('\\.')[0] : row.library
    meta.outdir     = (tol == 1) ? row.outdir : (row.outdir == "") ? "${params.outdir}" : row.outdir

    def platform = ""
    if (meta.datatype == "hic" || meta.datatype == "illumina") { platform = "ILLUMINA" }
    else if (meta.datatype == "pacbio" || meta.datatype == "pacbio_clr") { platform = "PACBIO" }
    else if (meta.datatype == "ont") { platform = "ONT" }
    meta.read_group  = "\'@RG\\tID:" + row.datafile.split('/')[-1].split('\\.')[0] + "\\tPL:" + platform + "\\tSM:" + meta.id.split('_')[0..-2].join('_') + "\'"

    def array = []
    array = [ meta, [ file(row.datafile) ] ]
    return array
}
