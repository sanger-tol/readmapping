//
// Align HiC read files against the genome
//

include { SAMTOOLS_FASTQ                        } from '../../modules/nf-core/modules/samtools/fastq/main'
include { BWAMEM2_MEM                           } from '../../modules/nf-core/modules/bwamem2/mem/main'
include { CONVERT_STATS as CONVERT_STATS_SINGLE } from '../../subworkflows/local/convert_stats'
include { MARKDUPLICATE                         } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS as CONVERT_STATS_MERGE  } from '../../subworkflows/local/convert_stats'

workflow ALIGN_HIC {
    take:
    reads // channel: [ val(meta), [ datafile ] ]
    index // channel: /path/to/bwamem2/
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Convert from CRAM to FASTQ
    SAMTOOLS_FASTQ ( reads )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())
    
    // Align Fastq to Genome
    BWAMEM2_MEM ( SAMTOOLS_FASTQ.out.fastq, index, true )
    ch_versions = ch_versions.mix(BWAMEM2_MEM.out.versions.first())

    // Convert to CRAM and calculate indices and statistics
    CONVERT_STATS_SINGLE ( BWAMEM2_MEM.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_SINGLE.out.versions.first())

    // Collect all BWAMEM2 output by sample name
    BWAMEM2_MEM.out.bam
    .map { meta, bam ->
    new_meta = meta.clone()
    new_meta.id = new_meta.id.split('_')[0..-2].join('_')
    [ [id: new_meta.id, datatype: new_meta.datatype] , bam ] 
    }   
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
