#!/usr/bin/env nextflow

//
// MODULE IMPORT BLOCK
//
include { CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT          } from '../../modules/local/cram_filter_align_bwamem2_fixmate_sort'
include { SAMTOOLS_MERGE                                  } from '../../modules/nf-core/samtools/merge/main'

workflow BWAMEM2_MAPREDUCE {
    take:
    fasta     // Channel: tuple [ val(meta), path( file )      ]
    csv_ch
    index


    main:
    ch_versions         = Channel.empty()
    mappedbam_ch        = Channel.empty()

    csv_ch
    | splitCsv()
    | map{ cram_id, cram_info ->
        tuple([
                id: cram_id.id,
                chunk_id: cram_id.id + "_" + cram_info[5]
                ],
            file(cram_info[0]),
            cram_info[1],
            cram_info[2],
            cram_info[3],
            cram_info[4],
            cram_info[5],
            cram_info[6]
        )
    }
    | set { ch_filtering_input }


    //
    // MODULE: Map hic reads in each chunk using bwamem2
    //
    CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT (
        ch_filtering_input,
        fasta,
        index
    )
    ch_versions         = ch_versions.mix ( CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT.out.versions )
    mappedbam_ch        = CRAM_FILTER_ALIGN_BWAMEM2_FIXMATE_SORT.out.mappedbam

    //
    // LOGIC: Preparing BAMs for merging
    //
    mappedbam_ch
    | map { meta, file -> [meta.id, meta, file] }
    | groupTuple()
    | map { id, metas, files -> [ metas[0] - [chunk_id: metas[0].chunk_id], files ] }
    | set { collected_files_for_merge }

    //
    // MODULE: Merge position sorted BAM files and mark duplicates
    //
    SAMTOOLS_MERGE (
        collected_files_for_merge,
        fasta,
        [ [], [] ],
        [ [], [] ]
    )
    ch_versions         = ch_versions.mix ( SAMTOOLS_MERGE.out.versions )


    emit:
    mergedbam           = SAMTOOLS_MERGE.out.bam
    versions            = ch_versions
}
