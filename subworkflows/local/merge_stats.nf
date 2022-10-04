//
// Merge all alignments at specimen level
// Convert to CRAM and calculate statistics
//
include { SAMTOOLS_MERGE } from '../../modules/nf-core/modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORT  } from '../../modules/nf-core/modules/nf-core/samtools/sort/main'
include { CONVERT_STATS  } from '../../subworkflows/local/convert_stats'

workflow MERGE_STATS {
    take:
    aln // channel: [ val(meta), [ bam ] ]
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Collect all alignment output by sample name
    aln.map { meta, bam ->
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
    SAMTOOLS_SORT ( SAMTOOLS_MERGE.out.bam )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS ( SAMTOOLS_SORT.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS.out.versions)

    emit:
    cram = CONVERT_STATS.out.cram
    crai = CONVERT_STATS.out.crai
    stats = CONVERT_STATS.out.stats
    idxstats = CONVERT_STATS.out.idxstats
    flagstat = CONVERT_STATS.out.flagstat
    versions = ch_versions
}
