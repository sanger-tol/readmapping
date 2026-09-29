//
// Check input samplesheet and get read channels
//

include { GUNZIP        } from '../../modules/nf-core/gunzip/main'
include { SAMTOOLS_FAIDX    } from '../../modules/nf-core/samtools/faidx/main'
include { SAMTOOLS_FLAGSTAT } from '../../modules/nf-core/samtools/flagstat/main'
include { MASK_UNMASK   } from '../../modules/sanger-tol/mask/unmask/main'

workflow INPUT_CHECK {
    take:
    ch_fasta    // channel: [ meta, /path/to/fasta ]
    ch_samplesheet    // channel: [ val(meta), /path/to/reads ]


    main:

    // Prepare the samplesheet channel for SAMTOOLS_FLAGSTAT
    samplesheet_rows = ch_samplesheet
    .map { meta, file -> [meta, file, []] }

    // Get stats from each input file
    SAMTOOLS_FLAGSTAT ( samplesheet_rows )

    // Create the read channel for the rest of the pipeline
    reads = samplesheet_rows
    .join( SAMTOOLS_FLAGSTAT.out.flagstat )
    .map { meta, datafile, _meta2, stats -> create_data_channel( meta, datafile, stats ) }

    // Uncompress genome fasta file if required
    ch_named_fasta = ch_fasta.branch { _meta, file ->
        gz: file.name.endsWith('.gz')
        fa: true
    }
    GUNZIP ( ch_named_fasta.gz )

    ch_fasta_for_faidx = GUNZIP.out.gunzip
        // Update the id of uncompressed files
        .map { meta, fa -> [meta + [id: fa.baseName], fa] }
        .mix( ch_named_fasta.fa )
        // Add the empty fai input for SAMTOOLS_FAIDX
        .map { meta, fa -> tuple(meta, fa, []) }

    SAMTOOLS_FAIDX ( ch_fasta_for_faidx, false )

    // Read the .fai file, extract sequence statistics, and make an extended meta map
    ch_fasta_for_unmask = ch_fasta_for_faidx
        .join(SAMTOOLS_FAIDX.out.fai)
        .map { meta, fa, _empty, fai -> tuple(meta + get_sequence_map(fai), fa) }
    MASK_UNMASK ( ch_fasta_for_unmask )

    emit:
    reads = reads                                 // channel: [ val(meta), /path/to/datafile ]
    fasta = MASK_UNMASK.out.unmasked.first()      // channel: [ meta, /path/to/fasta ]
}


// Function to get list of [ meta, reads ]
def create_data_channel ( LinkedHashMap row, datafile, stats ) {
    // create meta map
    def meta = [:]
    meta.specimen      = row.specimen
    meta.run           = row.run.replaceAll("#", "_")
    meta.id            = "${meta.specimen}.${meta.run}".replaceAll("#", "_")
    meta.sample        = meta.specimen
    meta.datatype      = row.datatype
    meta.library       = row.library
    meta.barcode       = row.barcode
    meta.adapter_file   = row.adapter_file   ?: null
    meta.adapter_preset = row.adapter_preset ?: null

    if (meta.library == 'pimms') {
        if (meta.adapter_file == null && meta.adapter_preset == null) {
            error "Sample ${meta.specimen}.${meta.run} is library=pimms: neither adapter_file nor adapter_preset are provided"
        } else if (meta.adapter_file != null && meta.adapter_preset == null) {
            error "Sample ${meta.specimen}.${meta.run} is library=pimms: adapter_file is provided but adapter_preset is missing"
        } else if (meta.adapter_file == null && meta.adapter_preset != null) {
            error "Sample ${meta.specimen}.${meta.run} is library=pimms: adapter_preset is provided but adapter_file is missing"
        }
    }

    def platform = (meta.datatype == "hic" || meta.datatype == "illumina") ? "ILLUMINA" :
                (meta.datatype == "pacbio" || meta.datatype == "pacbio_clr") ? "PACBIO" :
                (meta.datatype == "ont") ? "ONT" : "UNKNOWN"

    // Convert datafile to string path and then split
    meta.read_group  = "\'@RG\\tID:" + datafile.simpleName + "\\tPL:" + platform + "\\tSM:" + meta.specimen + "\'"

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

// Read the .fai file to extract the number of sequences, the maximum and total sequence length
// Inspired from https://github.com/nf-core/rnaseq/blob/3.10.1/lib/WorkflowRnaseq.groovy
def get_sequence_map(fai_file) {
    def n_sequences = 0
    def max_length = 0
    def total_length = 0
    fai_file.eachLine { line ->
        def lspl = line.split('\t')
        // def chrom  = lspl[0]
        def length = lspl[1].toLong()
        n_sequences += 1
        total_length += length
        if (length > max_length) {
            max_length = length
        }
    }

    def sequence_map = [:]
    sequence_map.n_sequences = n_sequences
    sequence_map.genome_size = total_length
    if (n_sequences) {
        sequence_map.max_length = max_length
    }
    return sequence_map
}
