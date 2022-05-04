//
// Filter PacBio reads
// Original protocol is a modified version by Shane of the original program, HiFiAdapterFilt
//

include { SAMTOOLS_PACBIO } from '../../modules/local/samtools/pacbio'
// include { PBBAM_PBINDEX   } from '../../modules/local/pbbam/pbindex'
include { SAMTOOLS_FASTA  } from '../../modules/local/samtools/fasta'
include { UNTAR           } from '../../modules/nf-core/modules/untar/main'
include { BLAST_BLASTN    } from '../../modules/nf-core/modules/blast/blastn/main'
include { PACBIO_FILTER   } from '../../modules/local/custom/pacbio_filter'
include { SAMTOOLS_FILTER } from '../../modules/local/samtools/filter'
include { SAMTOOLS_FASTQ  } from '../../modules/local/samtools/fastq'

workflow FILTER_PACBIO {
    take:
    bam
    blastDB

    main:
    ch_versions = Channel.empty()

    // Convert from PacBio BAM to Samtools BAM
    SAMTOOLS_PACBIO ( bam )
    ch_versions = ch_versions.mix(SAMTOOLS_PACBIO.out.versions.first())

    // Index Samtools BAM
    // PBBAM_PBINDEX ( SAMTOOLS_PACBIO.out.bam )
    // ch_versions = ch_versions.mix(PBBAM_PBINDEX.out.versions.first())

    // Convert BAM to FASTA
    SAMTOOLS_FASTA ( SAMTOOLS_PACBIO.out.bam )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTA.out.versions.first())

    // BLAST database
    ch_db = Channel.empty()
    if (blastDB.endsWith('.tar.gz')) {
        ch_db       = UNTAR (blastDB).untar
        ch_versions = ch_versions.mix(UNTAR.out.versions)
    } else {
        ch_db       = file(blastDB)
    }

    // Nucleotide BLAST
    BLAST_BLASTN ( SAMTOOLS_FASTA.out.fasta, ch_db )
    ch_versions = ch_versions.mix(BLAST_BLASTN.out.versions.first())

    // Filter BLAST output
    PACBIO_FILTER ( BLAST_BLASTN.out.txt )
    ch_versions = ch_versions.mix(PACBIO_FILTER.out.versions.first())

    // Create filtered BAM file
    SAMTOOLS_FILTER ( SAMTOOLS_PACBIO.out.bam, PACBIO_FILTER.out.list )
    ch_versions = ch_versions.mix(SAMTOOLS_FILTER.out.versions.first())

    // Convert BAM to FASTQ
    SAMTOOLS_FASTQ ( SAMTOOLS_FILTER.out.bam )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())

    emit:
    fastq    = SAMTOOLS_FASTQ.out.fastq 
    
    versions = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}
