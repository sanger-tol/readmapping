//
// Check input samplesheet and get read channels
//

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'


workflow INPUT_CHECK {
    take:
    samplesheet    // file: /path/to/samplesheet.csv


    main:
    SAMPLESHEET_CHECK ( samplesheet ).csv
    | splitCsv ( header:true, sep:',' )
    | map { create_data_channel( it ) }
    | set { reads }


    emit:
    reads                                        // channel: [ val(meta), /path/to/datafile ]
    versions = SAMPLESHEET_CHECK.out.versions    // channel: [ versions.yml ]
}


// Function to get list of [ meta, reads ]
def create_data_channel ( LinkedHashMap row ) {
    // create meta map
    def meta = [:]
    meta.id         = row.sample
    meta.datatype   = row.datatype

    if ( meta.datatype == "hic" || meta.datatype == "illumina" ) { 
        platform = "ILLUMINA"
    } else if ( meta.datatype == "pacbio" || meta.datatype == "pacbio_clr" ) { 
        platform = "PACBIO"
    } else if (meta.datatype == "ont") { 
        platform = "ONT"
    }
    meta.read_group  = "\'@RG\\tID:" + row.datafile.split('/')[-1].split('\\.')[0] + "\\tPL:" + platform + "\\tSM:" + meta.id.split('_')[0..-2].join('_') + "\'"


    // add path(s) of the read file(s) to the meta map
    def data_meta = []
    if ( !file(row.datafile).exists() ) {
        exit 1, "ERROR: Please check input samplesheet -> Data file does not exist!\n${row.datafile}"
    } else {
        data_meta = [ meta, file(row.datafile) ]
    }
    return data_meta
}
