//
// Convert to CRAM and calculate statistics
// Merge, markdup and repeat
//

include { CONVERT_STATS as CONVERT_STATS_FILE } from '../../subworkflows/local/convert_stats'
include { MARKDUPLICATE as MARKDUP_ID         } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS as CONVERT_STATS_ID   } from '../../subworkflows/local/convert_stats'
include { MARKDUPLICATE as MARKDUP_ALL        } from '../../subworkflows/local/markduplicate'
include { CONVERT_STATS as CONVERT_STATS_ALL  } from '../../subworkflows/local/convert_stats'

workflow STATS_MARKDUP {
    take:
    aln // channel: [ val(meta), [ datafile ] ]
    fasta // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Convert to CRAM and calculate indices and statistics
    CONVERT_STATS_FILE ( aln, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_FILE.out.versions)

    // Collect all BWAMEM2 output by sample name
    aln
    .map { meta, bam ->
    new_meta = meta.clone()
    new_meta.id = new_meta.id.split('_')[0..-2].join('_')
    [ [id: new_meta.id, datatype: new_meta.datatype] , bam ] 
    }   
    .groupTuple(by: [0])
    .set { ch_bams }

    // Mark duplicates
    MARKDUP_ID ( ch_bams )
    ch_versions = ch_versions.mix(MARKDUP_ID.out.versions)

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS_ID ( MARKDUP_ID.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_ID.out.versions)

    // Collect all merged bam output by sample name
    MARKDUP_ID.out.bam
    .map { meta, bam ->
    new_meta = meta.clone()
    new_meta.id = "all"
    [ [id: new_meta.id, datatype: new_meta.datatype] , bam ]
    }
    .groupTuple(by: [0])
    .set { ch_all }
    
    // Mark duplicates
    MARKDUP_ALL ( ch_all )
    ch_versions = ch_versions.mix(MARKDUP_ALL.out.versions)

    // Convert merged BAM to CRAM and calculate indices and statistics
    CONVERT_STATS_ALL ( MARKDUP_ALL.out.bam, fasta )
    ch_versions = ch_versions.mix(CONVERT_STATS_ALL.out.versions)

    emit:
    cram1 = CONVERT_STATS_FILE.out.cram
    crai1 = CONVERT_STATS_FILE.out.crai
    stats1 = CONVERT_STATS_FILE.out.stats
    idxstats1 = CONVERT_STATS_FILE.out.idxstats
    flagstat1 = CONVERT_STATS_FILE.out.flagstat

    cram2 = CONVERT_STATS_ID.out.cram
    crai2 = CONVERT_STATS_ID.out.crai
    stats2 = CONVERT_STATS_ID.out.stats
    idxstats2 = CONVERT_STATS_ID.out.idxstats
    flagstat2 = CONVERT_STATS_ID.out.flagstat

    cram3 = CONVERT_STATS_ALL.out.cram
    crai3 = CONVERT_STATS_ALL.out.crai
    stats3 = CONVERT_STATS_ALL.out.stats
    idxstats3 = CONVERT_STATS_ALL.out.idxstats
    flagstat3 = CONVERT_STATS_ALL.out.flagstat

    versions = ch_versions
}
