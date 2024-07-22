
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Local modules
//

include { SAMTOOLS_REHEADER           } from '../modules/local/samtools_replaceheader'


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
include { CONVERT_STATS                 } from '../subworkflows/local/convert_stats'


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

    take:
    ch_samplesheet
    ch_fasta
    ch_header

    main:
    // Initialize an empty versions channel
    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    INPUT_CHECK ( ch_samplesheet ).reads
    | branch {
        meta, reads ->
            hic : meta.datatype == "hic"
            illumina : meta.datatype == "illumina"
            pacbio : meta.datatype == "pacbio"
            clr : meta.datatype == "pacbio_clr"
            ont : meta.datatype == "ont"
    }
    | set { ch_reads }

    ch_versions = ch_versions.mix ( INPUT_CHECK.out.versions )


    //
    // SUBWORKFLOW: Uncompress and prepare reference genome files
    //
    ch_fasta
    | map { [ [ id: it.baseName ], it ] }
    | set { ch_genome }

    PREPARE_GENOME ( ch_genome )
    ch_versions = ch_versions.mix ( PREPARE_GENOME.out.versions )


    //
    // Create channel for vector DB
    //
    // ***PacBio condition does not work - needs fixing***
    if ( ch_reads.pacbio || ch_reads.clr ) {
        if ( params.vector_db.endsWith( '.tar.gz' ) ) {
            UNTAR ( [ [:], params.vector_db ] ).untar
            | set { ch_vector_db }

            ch_versions = ch_versions.mix ( UNTAR.out.versions )

        } else {
            Channel.fromPath ( params.vector_db )
            | set { ch_vector_db }
        }
    }


    //
    // SUBWORKFLOW: Align raw reads to genome
    //
    ALIGN_HIC ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.bwaidx, ch_reads.hic )
    ch_versions = ch_versions.mix ( ALIGN_HIC.out.versions )

    ALIGN_ILLUMINA ( PREPARE_GENOME.out.fasta, PREPARE_GENOME.out.bwaidx, ch_reads.illumina )
    ch_versions = ch_versions.mix ( ALIGN_ILLUMINA.out.versions )

    ALIGN_HIFI ( PREPARE_GENOME.out.fasta, ch_reads.pacbio, ch_vector_db )
    ch_versions = ch_versions.mix ( ALIGN_HIFI.out.versions )

    ALIGN_CLR ( PREPARE_GENOME.out.fasta, ch_reads.clr, ch_vector_db )
    ch_versions = ch_versions.mix ( ALIGN_CLR.out.versions )

    ALIGN_ONT ( PREPARE_GENOME.out.fasta, ch_reads.ont )
    ch_versions = ch_versions.mix ( ALIGN_ONT.out.versions )

    // gather alignments
    ch_aligned_bams = Channel.empty()
    | mix( ALIGN_HIC.out.bam )
    | mix( ALIGN_ILLUMINA.out.bam )
    | mix( ALIGN_HIFI.out.bam )
    | mix( ALIGN_CLR.out.bam )
    | mix( ALIGN_ONT.out.bam )

    // Optionally insert params.header information to bams
    ch_reheadered_bams = Channel.empty()
    if ( params.header ) {
        SAMTOOLS_REHEADER( ch_aligned_bams, ch_header.first() )
        ch_reheadered_bams = SAMTOOLS_REHEADER.out.bam
        ch_versions = ch_versions.mix ( SAMTOOLS_REHEADER.out.versions )
    } else {
        ch_reheadered_bams = ch_aligned_bams
    }

    // convert to cram and gather stats
    CONVERT_STATS ( ch_reheadered_bams, PREPARE_GENOME.out.fasta )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )


    //
    // MODULE: Combine different versions.yml
    //
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions
        | unique { it.text }
        | collectFile ( name: 'collated_versions.yml' )
    )
}



/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
