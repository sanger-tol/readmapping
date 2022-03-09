//
// Check input samplesheet and get read channels
//

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'

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
/*
    def platform = ""
    if (meta.datatype == "hic" || meta.datatype == "illumina") { platform = "ILLUMINA" }
    else if (meta.datatype == "pacbio") { platform = "PACBIO" }
    else if (meta.datatype == "ont") { platform = "ONT" }
    meta.readgroup  = "\'@RG\\tID:" + row.datafile.split('/')[-1] + "\\tPL:" + platform + "\\tSM:" + row.rgid + "\'"
*/
    def array = []
    array = [ meta, [ file(row.datafile) ] ]
    return array
}
