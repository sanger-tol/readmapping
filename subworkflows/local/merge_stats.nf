//
// Merge all alignments at specimen level
// Convert to CRAM and calculate statistics
//
include { SAMTOOLS_SORT as SINGLE_SORT } from '../../modules/local/samtools/sort'
include { SAMTOOLS_MERGE               } from '../../modules/nf-core/modules/samtools/merge/main'
include { SAMTOOLS_SORT as MERGE_SORT  } from '../../modules/local/samtools/sort'
include { CONVERT_STATS                } from '../../subworkflows/local/convert_stats'

workflow MERGE_STATS {
    take:
    aln // channel: [ val(meta), [ sam ] ]
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Sort SAM and convert to BAM
    SINGLE_SORT ( aln )
    ch_versions = ch_versions.mix(SINGLE_SORT.out.versions.first())

    // Collect all alignment output by sample name
    SINGLE_SORT.out.bam
    .map { meta, bam ->
    new_meta = meta.clone()
    new_meta.id = new_meta.id.split('_')[0..-2].join('_')
    [ [id: new_meta.id, datatype: new_meta.datatype] , bam ]
    }
    .groupTuple(by: [0])
    .set { ch_bams }

    // Merge
    SAMTOOLS_MERGE ( ch_bams, [] )
    ch_versions = ch_versions.mix(SAMTOOLS_MERGE.out.versions.first())

    // Position sort BAM file
    MERGE_SORT ( SAMTOOLS_MERGE.out.bam )
    ch_versions = ch_versions.mix(MERGE_SORT.out.versions.first())

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS ( MERGE_SORT.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS.out.versions)

    emit:
    cram = CONVERT_STATS.out.cram
    crai = CONVERT_STATS.out.crai
    stats = CONVERT_STATS.out.stats
    idxstats = CONVERT_STATS.out.idxstats
    flagstat = CONVERT_STATS.out.flagstat

    versions = ch_versions
}
