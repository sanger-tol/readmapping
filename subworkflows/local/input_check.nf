//
// Check input samplesheet and get read channels
//

include { SAMTOOLS_FLAGSTAT } from '../../modules/nf-core/samtools/flagstat/main'

workflow INPUT_CHECK {
    take:
    ch_samplesheet    // channel: [ val(meta), /path/to/reads ]


    main:
    ch_versions = channel.empty()

    // Prepare the samplesheet channel for SAMTOOLS_FLAGSTAT
    ch_samplesheet
    .map { meta, file -> [meta, file, []] }
    .set { samplesheet_rows }

    // Get stats from each input file
    SAMTOOLS_FLAGSTAT ( samplesheet_rows )
    ch_versions = ch_versions.mix ( SAMTOOLS_FLAGSTAT.out.versions.first() )

    // Create the read channel for the rest of the pipeline
    samplesheet_rows
    .join( SAMTOOLS_FLAGSTAT.out.flagstat )
    .map { meta, datafile, _meta, stats -> create_data_channel( meta, datafile, stats ) }
    .set { reads }


    emit:
    reads                                        // channel: [ val(meta), /path/to/datafile ]
    versions = ch_versions                       // channel: [ versions.yml ]
}


// Function to get list of [ meta, reads ]
def create_data_channel ( LinkedHashMap row, datafile, stats ) {
    // create meta map
    def meta = [:]
    meta.id         = row.sample
    meta.datatype   = row.datatype
    meta.library    = row.library
    meta.barcode    = row.barcode

    def platform = (meta.datatype == "hic" || meta.datatype == "illumina") ? "ILLUMINA" :
                (meta.datatype == "pacbio" || meta.datatype == "pacbio_clr") ? "PACBIO" :
                (meta.datatype == "ont") ? "ONT" : "UNKNOWN"

    // Convert datafile to string path and then split
    def datafile_path = datafile.toString()
    meta.read_group  = "\'@RG\\tID:" + datafile_path.split('/')[-1].split('\\.')[0] + "\\tPL:" + platform + "\\tSM:" + meta.id.split('_')[0..-2].join('_') + "\'"

    // Read the first line of the flagstat file
    // 3127898040 + 0 in total (QC-passed reads + QC-failed reads)
    // and make the sum of both integers
    stats.withReader { reader ->
        def line = reader.readLine()
        def lspl = line.split()
        def read_count = lspl[0].toLong() + lspl[2].toLong()
        meta.read_count = read_count
    }

    return [meta, datafile]
}
