//
// Align PacBio read files against the genome
//

include { BAM2FASTQ      } from '../../modules/local/bam2fastx/bam2fastq'
include { MINIMAP2_ALIGN } from '../../modules/local/minimap2/align'
include { MARKDUP_STATS  } from '../../subworkflows/local/markdup_stats'

workflow ALIGN_PACBIO {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/mmi
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // BAM index channel
    reads
    .map { meta, bam ->
    pbindex = bam[0] + ".pbi"
    }
    .set { pbindex_ch }

    // Convert from BAM to FASTQ
    BAM2FASTQ ( reads, pbindex_ch )
    ch_versions = ch_versions.mix(BAM2FASTQ.out.versions.first())
     
    // Align Fastq to Genome
    MINIMAP2_ALIGN ( BAM2FASTQ.out.fastq, fasta, index )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Merge, markdup, convert, and stats
    MARKDUP_STATS ( MINIMAP2_ALIGN.out.sam, fasta )
    ch_versions = ch_versions.mix(MARKDUP_STATS.out.versions)

    emit:
    cram = MARKDUP_STATS.out.cram
    crai = MARKDUP_STATS.out.crai
    stats = MARKDUP_STATS.out.stats
    idxstats = MARKDUP_STATS.out.idxstats
    flagstat = MARKDUP_STATS.out.flagstat

    versions = ch_versions
}
