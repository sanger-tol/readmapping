//
// Merge and Markdup all alignments at specimen level
// Convert to CRAM and calculate statistics
//
include { SAMTOOLS_SORT } from '../../modules/local/samtools/sort'
include { MARKDUPLICATE } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS } from '../../subworkflows/local/convert_stats'

workflow MARKDUP_STATS {
    take:
    aln // channel: [ val(meta), [ sam ] ]
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Sort SAM and convert to BAM
    SAMTOOLS_SORT ( aln )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    // Collect all BWAMEM2 output by sample name
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
    CONVERT_STATS ( MARKDUPLICATE.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS.out.versions)

    emit:
    cram = CONVERT_STATS.out.cram
    crai = CONVERT_STATS.out.crai
    stats = CONVERT_STATS.out.stats
    idxstats = CONVERT_STATS.out.idxstats
    flagstat = CONVERT_STATS.out.flagstat

    versions = ch_versions
}
