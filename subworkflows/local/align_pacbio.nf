//
// Align PacBio read files against the genome
//

include { FILTER_PACBIO  } from '../../subworkflows/local/filter_pacbio'
include { MINIMAP2_ALIGN } from '../../modules/nf-core/minimap2/align/main'
include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'
include { CONVERT_STATS  } from '../../subworkflows/local/convert_stats'


workflow ALIGN_PACBIO {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    reads    // channel: [ val(meta), /path/to/datafile ]
    db       // channel: /path/to/vector_db


    main:
    ch_versions = Channel.empty()


    // Filter BAM and output as FASTQ
    FILTER_PACBIO ( reads, db )
    ch_versions = ch_versions.mix ( FILTER_PACBIO.out.versions )


    // Align Fastq to Genome
    fasta
    | map { meta, file -> file }
    | set { ch_fasta }

    // Align with minimap2. bam_format is set to true, making the output a *sorted* BAM
    MINIMAP2_ALIGN ( FILTER_PACBIO.out.fastq, ch_fasta, true, false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )


    // Collect all alignment output by sample name
    MINIMAP2_ALIGN.out.bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], meta.read_count, bam] }
    | groupTuple ( by: [0] )
    | map { meta, read_counts, bams -> [meta + [read_count: read_counts.sum()], bams] }
    | branch {
        meta, bams ->
            single_bam: bams.size() == 1
            multi_bams: true
    }
    | set { ch_bams }


    // Merge, but only if there is more than 1 file
    SAMTOOLS_MERGE ( ch_bams.multi_bams, [ [], [] ], [ [], [] ] )
    ch_versions = ch_versions.mix ( SAMTOOLS_MERGE.out.versions.first() )


    // Convert merged BAM to CRAM and calculate indices and statistics
    SAMTOOLS_MERGE.out.bam
    | mix ( ch_bams.single_bam )
    | map { meta, bam -> [ meta, bam, [] ] }
    | set { ch_sort }

    CONVERT_STATS ( ch_sort, fasta )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )


    emit:
    cram     = CONVERT_STATS.out.cram        // channel: [ val(meta), /path/to/cram ]
    crai     = CONVERT_STATS.out.crai        // channel: [ val(meta), /path/to/crai ]
    stats    = CONVERT_STATS.out.stats       // channel: [ val(meta), /path/to/stats ]
    idxstats = CONVERT_STATS.out.idxstats    // channel: [ val(meta), /path/to/idxstats ]
    flagstat = CONVERT_STATS.out.flagstat    // channel: [ val(meta), /path/to/flagstat ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
