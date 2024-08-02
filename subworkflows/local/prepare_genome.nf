//
// Uncompress and prepare reference genome files
//

include { GUNZIP        } from '../../modules/nf-core/gunzip/main'
include { UNMASK        } from '../../modules/local/unmask'
include { UNTAR         } from '../../modules/nf-core/untar/main'
include { BWAMEM2_INDEX } from '../../modules/nf-core/bwamem2/index/main'


workflow PREPARE_GENOME {
    take:
    fasta    // channel: [ meta, /path/to/fasta ]

    main:
    ch_versions = Channel.empty()


    // Uncompress genome fasta file if required
    if ( params.fasta.endsWith('.gz') ) {
        ch_unzipped = GUNZIP ( fasta ).gunzip
        ch_versions = ch_versions.mix ( GUNZIP.out.versions )
    } else {
        ch_unzipped = fasta
    }

    ch_unzipped
    | map { meta, fa -> [ meta + [id: fa.baseName, genome_size: fa.size()], fa] }
    | set { ch_fasta }

    // Unmask genome fasta
    UNMASK ( ch_fasta )
    ch_versions = ch_versions.mix ( UNMASK.out.versions.first() )

    // Generate BWA index
    if ( checkShortReads( params.input ) ) {
        if ( params.bwamem2_index ) {
            Channel.fromPath ( params.bwamem2_index )
            | combine ( ch_fasta )
            | map { bwa, meta, fa -> [ meta, bwa ] }
            | set { ch_bwamem }

            if ( params.bwamem2_index.endsWith('.tar.gz') ) {
                ch_bwamem2_index = UNTAR ( ch_bwamem ).untar
                ch_versions      = ch_versions.mix ( UNTAR.out.versions.first() )
            } else {
                ch_bwamem2_index = ch_bwamem
            }

        } else {
            ch_bwamem2_index = BWAMEM2_INDEX ( UNMASK.out.fasta ).index
            ch_versions      = ch_versions.mix ( BWAMEM2_INDEX.out.versions.first() )
        }
    } else {
        ch_bwamem2_index = Channel.empty()
    }


    emit:
    fasta    = UNMASK.out.fasta.first()    // channel: [ meta, /path/to/fasta ]
    bwaidx   = ch_bwamem2_index.first()    // channel: [ meta, /path/to/bwamem2/index_dir/ ]
    versions = ch_versions                 // channel: [ versions.yml ]
}

//
// Check for short reads in the samplesheet
//
def checkShortReads(filePath, columnToCheck="datatype") {
    // Define the target values to check
    def valuesToCheck = ['illumina', 'hic']

    // Read the CSV file
    def csvLines = new File(filePath).readLines()

    // Extract the header and find the index of the column
    def header = csvLines[0].split(',')
    def columnIndex = header.findIndexOf { it == columnToCheck }

    // Check if the column index was found
    if (columnIndex == -1) {
        error("Column '${columnToCheck}' not found in the CSV header.")
    }

    // Check for the values in the specified column and return true if found
    def containsValues = csvLines[1..-1].any { line ->
        def columns = line.split(',')
        valuesToCheck.contains(columns[columnIndex].toLowerCase())
    }
    println(containsValues)
    return containsValues
}

