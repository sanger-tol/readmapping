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
    ch_versions         = Channel.empty()
    mappedbam_ch        = Channel.empty()


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
    csv_ch
        .splitCsv()
        .combine ( fasta )
        .combine ( MINIMAP2_INDEX.out.index )
        .map{ cram_id, cram_info, ref_id, ref_dir, mmi_id, mmi_path->
            tuple([
                    id: cram_id.id,
                    chunk_id: cram_id.id + "_" + cram_info[5],
                    genome_size: ref_id.genome_size
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
    .set { ch_filtering_input }


    //
    // MODULE: map hic reads by 10,000 container per time
    //
    CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT (
        ch_filtering_input

    )
    ch_versions         = ch_versions.mix( CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT.out.versions )
    mappedbam_ch        = CRAM_FILTER_MINIMAP2_FILTER5END_FIXMATE_SORT.out.mappedbam


    //
    // LOGIC: PREPARING BAMS FOR MERGE
    //
    mappedbam_ch
        .map{ meta, file ->
            tuple( file )
        }
        .collect()
        .map { file ->
            tuple (
                [
                id: file[0].toString().split('/')[-1].split('_')[0] + '_' + file[0].toString().split('/')[-1].split('_')[1]
                ],
                file
            )
        }
        .set { collected_files_for_merge }


    //
    // MODULE: MERGE POSITION SORTED BAM FILES AND MARK DUPLICATES
    //
    SAMTOOLS_MERGE (
        collected_files_for_merge,
        fasta,
        [ [], [] ]
    )
    ch_versions         = ch_versions.mix ( SAMTOOLS_MERGE.out.versions.first() )


    emit:
    mergedbam           = SAMTOOLS_MERGE.out.bam
    versions            = ch_versions.ifEmpty(null)
}
