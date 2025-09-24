//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//
params.filter_pacbio = ""
params.hifi_adapter_yaml = "${projectDir}/assets/HiFi_adapter.yaml"

include { BLAST_BLASTN as BLASTN_HIFI       } from '../../modules/nf-core/blast/blastn/main'                                                                                                                                                                                    
include { HIFI_TRIMMER                      } from '../../modules/local/hifi_trimmer'
include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_COLLATETOFASTA           } from '../../modules/local/samtools_collatetofasta'
include { SAMTOOLS_FASTQ                    } from '../../modules/nf-core/samtools/fastq/main'
include { TABIX_BGZIP as BGZIP_BLASTN       } from '../../modules/nf-core/tabix/bgzip/main'


workflow FILTER_PACBIO {
    take:
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db


    main:
    ch_versions = Channel.empty()

    // Convert from PacBio CRAM to Samtools CRAM
    reads
    | map { meta, cram -> [ meta, cram, [] ] }
    | set { ch_pacbio }

    SAMTOOLS_CONVERT ( ch_pacbio, [ [], [] ], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_CONVERT.out.versions )

    ch_bam_reads = SAMTOOLS_CONVERT.out.bam

    if ( params.filter_pacbio ) {
        // Collate BAM file to create interleaved FASTA
        SAMTOOLS_COLLATETOFASTA ( ch_bam_reads )

        BLASTN_HIFI( SAMTOOLS_COLLATETOFASTA.out.fasta, db )
        BGZIP_BLASTN( BLASTN_HIFI.out.txt )

        bam_blast = ch_bam_reads.join( BGZIP_BLASTN.out.output )

        HIFI_TRIMMER( bam_blast, params.hifi_adapter_yaml)

        ch_filtered_fastq =  HIFI_TRIMMER.out.fastq

        ch_versions = ch_versions
        | mix ( SAMTOOLS_COLLATETOFASTA.out.versions )
        | mix ( BLASTN_HIFI.out.versions )
        | mix ( BGZIP_BLASTN.out.versions )
        | mix ( HIFI_TRIMMER.out.versions )

    } else {
        // Extract FASTQ from BAM using a passthrough process
        SAMTOOLS_FASTQ ( ch_bam_reads, false )
        ch_versions = ch_versions.mix ( SAMTOOLS_FASTQ.out.versions )
        ch_filtered_fastq = SAMTOOLS_FASTQ.out.other
    }

    emit:
    fastq    = ch_filtered_fastq        // channel: [ meta, /path/to/fastq ]
    versions = ch_versions              // channel: [ versions.yml ]
}