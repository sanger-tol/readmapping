//
// Align short read (HiC and Illumina) data against the genome
//

include { SAMTOOLS_FASTQ                        } from '../../modules/nf-core/samtools/fastq/main'
include { SAMTOOLS_MERGE                        } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORMADUP                     } from '../../modules/local/samtools_sormadup'
include { SAMTOOLS_VIEW as SAMTOOLS_INDEX       } from '../../modules/nf-core/samtools/view/main'
include { GENERATE_CRAM_CSV                     } from '../../modules/local/generate_cram_csv'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM     } from '../../modules/local/samtools_sormadup'
include { HIC_MINIMAP2                          } from '../../subworkflows/local/hic_minimap2'
include { HIC_BWAMEM2                           } from '../../subworkflows/local/hic_bwamem2'

workflow ALIGN_SHORT_HIC {
    take: 
    fasta    // channel: [ val(meta), /path/to/fasta ] reference_tuple
    index    // channel: [ val(meta), /path/to/bwamem2/ ]
    reads    // channel: [ val(meta), /path/to/datafile ] hic_reads_path


    main:
    ch_versions = Channel.empty()
    ch_merged_bam   = Channel.empty()

    // Check file types and branch
    reads
    | branch {
        meta, reads ->
            fastq : reads.findAll { it.getName().toLowerCase() =~ /.*f.*\.gz/ }
            cram : true
    }
    | set { ch_reads }


    // Convert FASTQ to CRAM only if FASTQ were provided as input
    CONVERT_CRAM ( ch_reads.fastq, fasta )
    ch_versions = ch_versions.mix (    CONVERT_CRAM.out.versions.first() )

    CONVERT_CRAM.out.bam
    | mix ( ch_reads.cram )
    | map { meta, cram -> [ meta, cram, [] ] }
    | set { ch_reads_cram }

    // Index the CRAM file
    SAMTOOLS_INDEX ( ch_reads_cram, fasta, [] )
    ch_versions         = ch_versions.mix( SAMTOOLS_INDEX.out.versions )

    SAMTOOLS_INDEX.out.cram
    | join ( SAMTOOLS_INDEX.out.crai )
    | set { ch_reads_cram }


    //
    // MODULE: generate a CRAM CSV file containing the required parametres for CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT
    //
    GENERATE_CRAM_CSV( ch_reads_cram )
    ch_versions         = ch_versions.mix( GENERATE_CRAM_CSV.out.versions )


    //
    // SUBWORKFLOW: mapping hic reads using minimap2 or bwamem2
    //
    if (params.hic_aligner == 'minimap2') {
        HIC_MINIMAP2 (
            fasta,
            GENERATE_CRAM_CSV.out.csv,
            index
        )
        ch_versions         = ch_versions.mix( HIC_MINIMAP2.out.versions )
        ch_merged_bam           = ch_merged_bam.mix(HIC_MINIMAP2.out.mergedbam)
    } else {
        HIC_BWAMEM2 (
            fasta,
            GENERATE_CRAM_CSV.out.csv,
            index
        )
        ch_versions         = ch_versions.mix( HIC_BWAMEM2.out.versions )
        ch_merged_bam           = ch_merged_bam.mix(HIC_BWAMEM2.out.mergedbam)
    }
    
    ch_merged_bam
    | combine( ch_reads_cram )
    | map { meta_bam, bam, meta_cram, cram, crai -> [ meta_cram, bam ] }
    | set { ch_merged_bam }
    
    // // Collect all BWAMEM2 output by sample name
    ch_merged_bam
    | map { meta, bam -> [['id': meta.id.split('_')[0..-2].join('_'), 'datatype': meta.datatype], meta.read_count, bam] }
    | groupTuple( by: [0] )
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


    SAMTOOLS_MERGE.out.bam
    | mix ( ch_bams.single_bam )
    | set { ch_bam }


    // Mark duplicates
    SAMTOOLS_SORMADUP ( ch_bam, fasta )
    ch_versions = ch_versions.mix ( SAMTOOLS_SORMADUP.out.versions )

    emit:
    bam      = SAMTOOLS_SORMADUP.out.bam     // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
