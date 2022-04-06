//
// Check input samplesheet and get read channels
//

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet/check'

workflow INPUT_CHECK {
    take:
    samplesheet // file: /path/to/samplesheet.csv

    main:
    SAMPLESHEET_CHECK ( samplesheet )
        .csv
        .splitCsv ( header:true, sep:',' )
        .map { create_data_channels(it) }
        .set { reads }

    emit:
    reads                                     // channel: [ val(meta), [ reads ] ]
    versions = SAMPLESHEET_CHECK.out.versions // channel: [ versions.yml ]
}

// Function to get list of [ meta, [ datafile ] ]
def create_data_channels(LinkedHashMap row) {
    def meta = [:]
    meta.id         = row.sample
    meta.datatype   = row.datatype
    meta.library    = (row.library == "") ? row.datafile.split('/')[-1].split('\\.')[0] : row.library

    def platform = ""
    if (meta.datatype == "hic" || meta.datatype == "illumina") { platform = "ILLUMINA" }
    else if (meta.datatype == "pacbio" || meta.datatype == "pacbio_clr") { platform = "PACBIO" }
    else if (meta.datatype == "ont") { platform = "ONT" }
    meta.read_group  = "\'@RG\\tID:" + row.datafile.split('/')[-1].split('\\.')[0] + "\\tPL:" + platform + "\\tSM:" + meta.id.split('_')[0..-2].join('_') + "\'"

    def array = []
    array = [ meta, [ file(row.datafile) ] ]
    return array
}
