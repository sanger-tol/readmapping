//
// Align HiC read files against the genome
//

include { SAMTOOLS_FASTQ                        } from '../../modules/nf-core/modules/samtools/fastq/main'
include { MINIMAP2_ALIGN                        } from '../../modules/local/minimap2_align'
include { SAMTOOLS_SORT                         } from '../../modules/nf-core/modules/samtools/sort/main'
include { CONVERT_STATS as CONVERT_STATS_SINGLE } from '../../subworkflows/local/convert_stats'
include { MARKDUPLICATE                         } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS as CONVERT_STATS_MERGE  } from '../../subworkflows/local/convert_stats'

workflow ALIGN_PACBIO {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/mmi
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Convert from BAM to FASTQ
    SAMTOOLS_FASTQ ( reads )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())
    
    // Align Fastq to Genome
    MINIMAP2_ALIGN ( SAMTOOLS_FASTQ.out.fastq, fasta )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Convert and Sort aligned file
    SAMTOOLS_SORT ( MINIMAP2_ALIGN.out.sam )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    // Convert to CRAM and calculate indices and statistics
    CONVERT_STATS_SINGLE ( SAMTOOLS_SORT.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_SINGLE.out.versions.first())

    // Collect all MINIMAP2 + SAMTOOLS output by sample name
    SAMTOOLS_SORT.out.bam
    .map { meta, bam -> meta.id = meta.id.split('_')[0..-2].join('_')[ meta, bam ] }
    .groupTuple(by: [0])
    .set { ch_bams }

    // Mark duplicates
    MARKDUPLICATE ( ch_bams )
    ch_versions = ch_versions.mix(MARKDUPLICATE.out.versions.first())

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS_MERGE ( MARKDUPLICATE.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_MERGE.out.versions.first())

    emit:
    cram1 = CONVERT_STATS_SINGLE.out.cram
    crai1 = CONVERT_STATS_SINGLE.out.crai
/*
    stats1 = CONVERT_STATS_SINGLE.out.stats
    idxstats1 = CONVERT_STATS_SINGLE.out.idxstats
    flagstats1 = CONVERT_STATS_SINGLE.out.flagstats
*/
    cram = CONVERT_STATS_MERGE.out.cram
    crai = CONVERT_STATS_MERGE.out.crai
/*
    stats = CONVERT_STATS_MERGE.out.stats
    idxstats = CONVERT_STATS_MERGE.out.idxstats
    flagstats = CONVERT_STATS_MERGE.out.flagstats
*/
    versions = ch_versions
}
