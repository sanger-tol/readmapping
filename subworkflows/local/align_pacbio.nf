//
// Align PacBio read files against the genome
//

include { FILTER_PACBIO  } from '../../subworkflows/local/filter_pacbio'
include { MINIMAP2_ALIGN } from '../../modules/nf-core/minimap2/align/main'
include { SAMTOOLS_MERGE } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORT  } from '../../modules/nf-core/samtools/sort/main'
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

    MINIMAP2_ALIGN ( FILTER_PACBIO.out.fastq, ch_fasta, true, false, false )
    ch_versions = ch_versions.mix ( MINIMAP2_ALIGN.out.versions.first() )


    // Collect all alignment output by sample name
    MINIMAP2_ALIGN.out.bam
    | map { meta, bam ->
         new_id = meta.id.split('_')[0..-2].join('_')
         [ meta + [ id: new_id ] , bam ] }
    | map { meta, bam -> [ [ meta.id, meta.datatype ], bam ] }
    | groupTuple ( by: [0] )
    | set { ch_bams }


    // Merge
    SAMTOOLS_MERGE ( ch_bams, [], [] )
    ch_versions = ch_versions.mix ( SAMTOOLS_MERGE.out.versions.first() )


    // Position sort BAM file
    SAMTOOLS_SORT ( SAMTOOLS_MERGE.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_SORT.out.versions.first() )


    // Convert merged BAM to CRAM and calculate indices and statistics
    SAMTOOLS_SORT.out.bam
    | map { meta, bam -> [ meta, bam, [] ] }
    | set { ch_sort }

    CONVERT_STATS ( ch_sort, ch_fasta )
    ch_versions = ch_versions.mix ( CONVERT_STATS.out.versions )


    emit:
    cram     = CONVERT_STATS.out.cram        // channel: [ val(meta), /path/to/cram ]
    crai     = CONVERT_STATS.out.crai        // channel: [ val(meta), /path/to/crai ]
    stats    = CONVERT_STATS.out.stats       // channel: [ val(meta), /path/to/stats ]
    idxstats = CONVERT_STATS.out.idxstats    // channel: [ val(meta), /path/to/idxstats ]
    flagstat = CONVERT_STATS.out.flagstat    // channel: [ val(meta), /path/to/flagstat ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
