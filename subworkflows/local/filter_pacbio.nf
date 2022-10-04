//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//

include { SAMTOOLS_VIEW as SAMTOOLS_CONVERT } from '../../modules/nf-core/modules/nf-core/samtools/view/main'
include { SAMTOOLS_FASTA                    } from '../../modules/nf-core/modules/nf-core/samtools/fasta/main'
include { BLAST_BLASTN                      } from '../../modules/nf-core/modules/nf-core/blast/blastn/main'
include { PACBIO_FILTER                     } from '../../modules/local/custom/pacbio_filter'
include { SAMTOOLS_VIEW as SAMTOOLS_FILTER  } from '../../modules/nf-core/modules/nf-core/samtools/view/main'
include { SAMTOOLS_FASTQ                    } from '../../modules/nf-core/modules/nf-core/samtools/fastq/main'

workflow FILTER_PACBIO {
    take:
    bam
    vector_db

    main:
    ch_versions = Channel.empty()

    // Convert from PacBio BAM to Samtools BAM
    SAMTOOLS_CONVERT ( bam, [], [] )
    ch_versions = ch_versions.mix(SAMTOOLS_CONVERT.out.versions.first())

    // Convert BAM to FASTA
    SAMTOOLS_FASTA ( SAMTOOLS_CONVERT.out.bam )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTA.out.versions.first())

    // Nucleotide BLAST
    BLAST_BLASTN ( SAMTOOLS_FASTA.out.fasta, vector_db )
    ch_versions = ch_versions.mix(BLAST_BLASTN.out.versions.first())

    // Filter BLAST output
    PACBIO_FILTER ( BLAST_BLASTN.out.txt )
    ch_versions = ch_versions.mix(PACBIO_FILTER.out.versions.first())

    // Create filtered BAM file
    SAMTOOLS_FILTER ( SAMTOOLS_PACBIO.out.bam, [], PACBIO_FILTER.out.list )
    ch_versions = ch_versions.mix(SAMTOOLS_FILTER.out.versions.first())

    // Convert BAM to FASTQ
    SAMTOOLS_FASTQ ( SAMTOOLS_FILTER.out.bam )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())

    emit:
    fastq    = SAMTOOLS_FASTQ.out.fastq  // channel: [ meta, fastq ]
    versions = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}
