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
include { SEQTK_SUBSEQ                      } from '../../modules/nf-core/seqtk/subseq'


workflow FILTER_PACBIO {
    take:
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db


    main:
    ch_versions = Channel.empty()


    // Check file types and branch
    reads
    | branch {
        meta, reads ->
            fastq : reads.findAll { it.getName().toLowerCase() =~ /.*f.*\.gz/ }
            bam : true
    }
    | set { ch_reads }


    // Convert from PacBio BAM to Samtools BAM
    ch_reads.bam
    | map { meta, bam -> [ meta, bam, [] ] }
    | set { ch_pacbio }

    SAMTOOLS_CONVERT ( ch_pacbio, [ [], [] ], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_CONVERT.out.versions.first() )


    // Collate BAM file to create interleaved FASTA
    SAMTOOLS_COLLATETOFASTA ( SAMTOOLS_CONVERT.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_COLLATETOFASTA.out.versions.first() )


    // Convert FASTQ to FASTA using SEQKIT_FQ2FA
    SEQKIT_FQ2FA ( ch_reads.fastq )
    ch_versions = ch_versions.mix ( SEQKIT_FQ2FA.out.versions.first() )


    // Combine BAM-derived FASTA with converted FASTQ inputs
    SAMTOOLS_COLLATETOFASTA.out.fasta
    | concat( SEQKIT_FQ2FA.out.fasta )
    | set { ch_fasta }


    // Nucleotide BLAST
    BLAST_BLASTN ( ch_fasta, db )
    ch_versions = ch_versions.mix ( BLAST_BLASTN.out.versions.first() )


    // Filter BLAST output
    PACBIO_FILTER ( BLAST_BLASTN.out.txt )
    ch_versions = ch_versions.mix ( PACBIO_FILTER.out.versions.first() )


    // Filter the BAM files and convert to FASTQ
    SAMTOOLS_CONVERT.out.bam
    | join ( SAMTOOLS_CONVERT.out.csi )
    | join ( PACBIO_FILTER.out.list )
    | multiMap { meta, bam, csi, list -> \
            bams: [meta, bam, csi]
            lists: list
    }
    | set { ch_bam_reads }

    SAMTOOLS_FILTERTOFASTQ ( ch_bam_reads.bams, ch_bam_reads.lists )
    ch_versions = ch_versions.mix ( SAMTOOLS_FILTERTOFASTQ.out.versions.first() )


    // Filter inputs provided as FASTQ
    ch_reads.fastq
    | join(PACBIO_FILTER.out.list)
    | multiMap { meta, fastq, list -> \
            fastqs: [meta, fastq]
            lists: list
    }
    | set { ch_reads_fastq }

    SEQTK_SUBSEQ ( ch_reads_fastq.fastqs, ch_reads_fastq.lists )
    ch_versions = ch_versions.mix ( SEQTK_SUBSEQ.out.versions.first() )


    // Merge filtered outputs as ch_output_fastq
    SEQTK_SUBSEQ.out.sequences
    | concat ( SAMTOOLS_FILTERTOFASTQ.out.fastq )
    | set { ch_filtered_fastq }


    emit:
    fastq    = ch_filtered_fastq        // channel: [ meta, /path/to/fastq ]
    versions = ch_versions              // channel: [ versions.yml ]
}
