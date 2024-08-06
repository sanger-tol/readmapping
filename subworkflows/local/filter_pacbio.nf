//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//

include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_COLLATETOFASTA           } from '../../modules/local/samtools_collatetofasta'
include { MINIMAP2_SPLICE                   } from '../../modules/local/minimap2_splice'
include { PACBIO_FILTER                     } from '../../modules/local/pacbio_filter'
include { SAMTOOLS_FILTERTOFASTQ            } from '../../modules/local/samtools_filtertofastq'


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


    // // Nucleotide BLAST
    // BLAST_BLASTN ( SAMTOOLS_COLLATETOFASTA.out.fasta, db )
    // ch_versions = ch_versions.mix ( BLAST_BLASTN.out.versions.first() )

    // Minimap2 splice
    MINIMAP2_SPLICE ( SAMTOOLS_COLLATETOFASTA.out.fasta, db )
    ch_versions = ch_versions.mix ( MINIMAP2_SPLICE.out.versions.first() )


    // Filter BLAST output
    PACBIO_FILTER ( MINIMAP2_SPLICE.out.paf )
    ch_versions = ch_versions.mix ( PACBIO_FILTER.out.versions.first() )


    // Filter the BAM file and convert to FASTQ
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

    SAMTOOLS_FILTERTOFASTQ ( ch_reads, ch_lists )
    ch_versions = ch_versions.mix ( SAMTOOLS_FILTERTOFASTQ.out.versions.first() )


    emit:
    fastq    = SAMTOOLS_FILTERTOFASTQ.out.fastq     // channel: [ meta, /path/to/fastq ]
    versions = ch_versions                          // channel: [ versions.yml ]
}
