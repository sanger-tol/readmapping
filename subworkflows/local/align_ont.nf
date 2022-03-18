//
// Align HiC read files against the genome
//

include { MINIMAP2_ALIGN                        } from '../../modules/local/minimap2/align'
include { SAMTOOLS_SORT                         } from '../../modules/nf-core/modules/samtools/sort/main'
include { CONVERT_STATS as CONVERT_STATS_SINGLE } from '../../subworkflows/local/convert_stats'
include { MARKDUPLICATE                         } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS as CONVERT_STATS_MERGE  } from '../../subworkflows/local/convert_stats'

workflow ALIGN_ONT {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/mmi
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Align Fastq to Genome
    MINIMAP2_ALIGN ( reads, fasta, index )
    ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions.first())

    // Add header to minimap2 sam
    SAMTOOLS_SORT ( MINIMAP2_ALIGN.out.sam )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    // Convert to CRAM and calculate indices and statistics
    CONVERT_STATS_SINGLE ( SAMTOOLS_SORT.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_SINGLE.out.versions)

    // Collect all MINIMAP2 output by sample name
    SAMTOOLS_SORT.out.bam
    .map { meta, bam ->
    new_meta = meta.clone()
    new_meta.id = new_meta.id.split('_')[0..-2].join('_')
    [ [id: new_meta.id, datatype: new_meta.datatype] , bam ] 
    }   
    .groupTuple(by: [0])
    .set { ch_bams }

    // Mark duplicates
    MARKDUPLICATE ( ch_bams )
    ch_versions = ch_versions.mix(MARKDUPLICATE.out.versions)

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS_MERGE ( MARKDUPLICATE.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_MERGE.out.versions)

    emit:
    cram1 = CONVERT_STATS_SINGLE.out.cram
    crai1 = CONVERT_STATS_SINGLE.out.crai
    stats1 = CONVERT_STATS_SINGLE.out.stats
    idxstats1 = CONVERT_STATS_SINGLE.out.idxstats
    flagstat1 = CONVERT_STATS_SINGLE.out.flagstat

    cram = CONVERT_STATS_MERGE.out.cram
    crai = CONVERT_STATS_MERGE.out.crai
    stats = CONVERT_STATS_MERGE.out.stats
    idxstats = CONVERT_STATS_MERGE.out.idxstats
    flagstat = CONVERT_STATS_MERGE.out.flagstat

    versions = ch_versions
}
