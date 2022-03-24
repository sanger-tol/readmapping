//
// Align HiC read files against the genome
//

include { BAM2FASTQ      } from '../../modules/local/bam2fastx/bam2fastq'
include { MINIMAP2_ALIGN } from '../../modules/local/minimap2/align'
include { SAMTOOLS_SORT  } from '../../modules/nf-core/modules/samtools/sort/main'
include { STATS_MARKDUP  } from '../../subworkflows/local/stats_markdup'

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
    BAM2FASTQ ( reads , pbindex_ch )
    ch_versions = ch_versions.mix(BAM2FASTQ.out.versions.first())
     
    // Align Fastq to Genome
    MINIMAP2_ALIGN ( BAM2FASTQ.out.fastq, fasta, index )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Add header to minimap2 sam
    SAMTOOLS_SORT ( MINIMAP2_ALIGN.out.sam )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    // Convert to CRAM, calculate indices and statistics, merge, markdup, and repeat
    STATS_MARKDUP ( SAMTOOLS_SORT.out.bam, fasta )
    ch_versions = ch_versions.mix(STATS_MARKDUP.out.versions)

    emit:
    cram1 = STATS_MARKDUP.out.cram1
    crai1 = STATS_MARKDUP.out.crai1
    stats1 = STATS_MARKDUP.out.stats1
    idxstats1 = STATS_MARKDUP.out.idxstats1
    flagstat1 = STATS_MARKDUP.out.flagstat1

    cram2 = STATS_MARKDUP.out.cram2
    crai2 = STATS_MARKDUP.out.crai2
    stats2 = STATS_MARKDUP.out.stats2
    idxstats2 = STATS_MARKDUP.out.idxstats2
    flagstat2 = STATS_MARKDUP.out.flagstat2

    cram3 = STATS_MARKDUP.out.cram3
    crai3 = STATS_MARKDUP.out.crai3
    stats3 = STATS_MARKDUP.out.stats3
    idxstats3 = STATS_MARKDUP.out.idxstats3
    flagstat3 = STATS_MARKDUP.out.flagstat3

    versions = ch_versions
}
