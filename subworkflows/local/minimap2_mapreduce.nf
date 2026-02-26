#!/usr/bin/env nextflow

//
// MODULE IMPORT BLOCK
//
include { CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT    } from '../../modules/local/cram_filter_minimap2_filter5end_fixmate_sort'
include { SAMTOOLS_MERGE                                  } from '../../modules/nf-core/samtools/merge/main'
include { MINIMAP2_INDEX                                  } from '../../modules/nf-core/minimap2/index/main'


workflow MINIMAP2_MAPREDUCE {
    take:
    fasta    // Channel: tuple [ val(meta), path( file )      ]
    csv_ch


    main:
    ch_versions         = channel.empty()
    mappedbam_ch        = channel.empty()

    //
    // MODULE: generate minimap2 mmi file
    //
    MINIMAP2_INDEX (
        fasta
        )
    ch_versions         = ch_versions.mix( MINIMAP2_INDEX.out.versions )

    //
    // LOGIC: generate input channel for mapping
    //
    ch_filtering_input = csv_ch
    .splitCsv()
    .combine ( fasta )
    .combine ( MINIMAP2_INDEX.out.index )
    .map{ cram_id, cram_info, ref_id, ref_dir, _mmi_id, mmi_path->
        tuple([
                id: cram_id.id,
                specimen: cram_id.specimen,
                library: cram_id.library,
                sample: cram_id.sample,
                run: cram_id.run,
                chunk_id: cram_id.id + "_" + cram_info[5],
                genome_size: ref_id.genome_size,
                datatype: cram_id.datatype
                ],
            file(cram_info[0]),
            cram_info[1],
            cram_info[2],
            cram_info[3],
            cram_info[4],
            cram_info[5],
            cram_info[6],
            mmi_path.toString(),
            ref_dir
        )
    }

    //
    // MODULE: Map hic reads by 10,000 container per time
    //
    CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT (
        ch_filtering_input
    )
    ch_versions         = ch_versions.mix( CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT.out.versions )
    mappedbam_ch        = CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT.out.mappedbam

    //
    // LOGIC: Preparing BAMs for merging
    //
    collected_files_for_merge = mappedbam_ch
    .map { meta, file -> [meta.id, meta, file] }
    .groupTuple()
    .map { _id, metas, files -> [ metas[0] - [chunk_id: metas[0].chunk_id], files ] }

    //
    // MODULE: Merge position sorted BAM files and mark duplicates
    //
    SAMTOOLS_MERGE (
        collected_files_for_merge,
        fasta,
        [ [], [] ],
        [ [], [] ]
    )


    emit:
    mergedbam           = SAMTOOLS_MERGE.out.bam
    versions            = ch_versions
}
