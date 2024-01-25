//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//

include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_COLLATETOFASTA           } from '../../modules/local/samtools_collatetofasta'
include { BLAST_BLASTN                      } from '../../modules/nf-core/blast/blastn/main'
include { PACBIO_FILTER                     } from '../../modules/local/pacbio_filter'
include { SAMTOOLS_VIEW as SAMTOOLS_FILTER  } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_FASTQ                    } from '../../modules/nf-core/samtools/fastq/main'


workflow FILTER_PACBIO {
    take:
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db


    main:
    ch_versions = Channel.empty()


    // Convert from PacBio BAM to Samtools BAM
    reads
    | map { meta, bam -> [ meta, bam, [] ] }
    | set { ch_pacbio }

    SAMTOOLS_CONVERT ( ch_pacbio, [ [], [] ], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_CONVERT.out.versions.first() )


    // Collate BAM file to create interleaved FASTA
    SAMTOOLS_COLLATETOFASTA ( SAMTOOLS_CONVERT.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_COLLATETOFASTA.out.versions.first() )


    // Nucleotide BLAST
    BLAST_BLASTN ( SAMTOOLS_COLLATETOFASTA.out.fasta, db )
    ch_versions = ch_versions.mix ( BLAST_BLASTN.out.versions.first() )


    // Filter BLAST output
    PACBIO_FILTER ( BLAST_BLASTN.out.txt )
    ch_versions = ch_versions.mix ( PACBIO_FILTER.out.versions.first() )


    // Create filtered BAM file
    SAMTOOLS_CONVERT.out.bam
    | join ( SAMTOOLS_CONVERT.out.csi )
    | join ( PACBIO_FILTER.out.list )
    | set { ch_reads_and_list }

    ch_reads_and_list
    | map { meta, bam, csi, list -> [meta, bam, csi] }
    | set { ch_reads }

    ch_reads_and_list
    | map { meta, bam, csi, list -> list }
    | set { ch_lists }

    SAMTOOLS_FILTER ( ch_reads, [ [], [] ], ch_lists )
    ch_versions = ch_versions.mix ( SAMTOOLS_FILTER.out.versions.first() )


    // Convert BAM to FASTQ
    SAMTOOLS_FASTQ ( SAMTOOLS_FILTER.out.unoutput, true )
    ch_versions = ch_versions.mix ( SAMTOOLS_FASTQ.out.versions.first() )


    emit:
    fastq    = SAMTOOLS_FASTQ.out.other    // channel: [ meta, /path/to/fastq ]
    versions = ch_versions                 // channel: [ versions.yml ]
}
