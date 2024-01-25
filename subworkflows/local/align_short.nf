//
// Align short read (HiC and Illumina) data against the genome
//

include { SAMTOOLS_FASTQ } from '../../modules/nf-core/samtools/fastq/main'
include { BWAMEM2_MEM    } from '../../modules/nf-core/bwamem2/mem/main'
include { MARKDUP_STATS  } from '../../subworkflows/local/markdup_stats'


workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    index    // channel: [ val(meta), /path/to/bwamem2/ ]
    reads    // channel: [ val(meta), /path/to/datafile ]


    main:
    ch_versions = Channel.empty()


    // Convert from CRAM to FASTQ
    SAMTOOLS_FASTQ ( reads, false )
    ch_versions = ch_versions.mix ( SAMTOOLS_FASTQ.out.versions.first() )


    // Align Fastq to Genome
    BWAMEM2_MEM ( SAMTOOLS_FASTQ.out.fastq, index, [] )
    ch_versions = ch_versions.mix ( BWAMEM2_MEM.out.versions.first() )


    // Merge, markdup, convert, and stats
    MARKDUP_STATS ( BWAMEM2_MEM.out.bam, fasta )
    ch_versions = ch_versions.mix ( MARKDUP_STATS.out.versions )


    emit:
    bam      = MARKDUP_STATS.out.bam         // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
