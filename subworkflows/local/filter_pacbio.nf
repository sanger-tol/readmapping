//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//

include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/samtools/view/main'
include { SAMTOOLS_COLLATETOFASTA           } from '../../modules/local/samtools_collatetofasta'
include { BLAST_BLASTN                      } from '../../modules/nf-core/blast/blastn/main'
include { PACBIO_FILTER                     } from '../../modules/local/pacbio_filter'
include { SAMTOOLS_FILTERTOFASTQ            } from '../../modules/local/samtools_filtertofastq'
include { SEQKIT_FQ2FA                      } from '../../modules/nf-core/seqkit/fq2fa'
include { BBMAP_FILTERBYNAME                } from '../../modules/nf-core/bbmap/filterbyname'


workflow FILTER_PACBIO {
    take:
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db

    main:
    ch_versions = Channel.empty()

    // Convert from PacBio CRAM to Samtools BAM
    reads
    | map { meta, cram -> [ meta, cram, [] ] }
    | set { ch_pacbio }

    SAMTOOLS_CONVERT ( ch_pacbio, [ [], [] ], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_CONVERT.out.versions )

    // Collate BAM file to create interleaved FASTA
    SAMTOOLS_COLLATETOFASTA ( SAMTOOLS_CONVERT.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_COLLATETOFASTA.out.versions )

    // Combine BAM-derived FASTA
    SAMTOOLS_COLLATETOFASTA.out.fasta
    | set { ch_fasta }

    // Nucleotide BLAST
    BLAST_BLASTN ( ch_fasta, db )
    ch_versions = ch_versions.mix ( BLAST_BLASTN.out.versions )

    // Filter BLAST output
    PACBIO_FILTER ( BLAST_BLASTN.out.txt )
    ch_versions = ch_versions.mix ( PACBIO_FILTER.out.versions )

    // Filter the input BAM and output as interleaved FASTA
    SAMTOOLS_CONVERT.out.bam
    | join ( SAMTOOLS_CONVERT.out.csi )
    | join ( PACBIO_FILTER.out.list )
    | multiMap { meta, bam, csi, list -> \
            bams: [meta, bam, csi]
            lists: list
    }
    | set { ch_bam_reads }

    SAMTOOLS_FILTERTOFASTQ ( ch_bam_reads.bams, ch_bam_reads.lists )
    ch_versions = ch_versions.mix ( SAMTOOLS_FILTERTOFASTQ.out.versions )

    // Merge filtered outputs as ch_output_fastq
    SAMTOOLS_FILTERTOFASTQ.out.fastq
    | set { ch_filtered_fastq }

    emit:
    fastq    = ch_filtered_fastq        // channel: [ meta, /path/to/fastq ]
    versions = ch_versions              // channel: [ versions.yml ]
}
