include { CRAMALIGN_GENCRAMCHUNKS         } from '../../../modules/sanger-tol/cramalign/gencramchunks'
include { CRAMALIGN_MINIMAP2ALIGN         } from '../../../modules/sanger-tol/cramalign/minimap2align/main'
include { MINIMAP2_INDEX                  } from '../../../modules/nf-core/minimap2/index/main'
include { SAMTOOLS_INDEX                  } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_SPLITHEADER            } from '../../../modules/nf-core/samtools/splitheader/main'

include { BAM_SAMTOOLS_MERGE_MARKDUP } from '../bam_samtools_merge_markdup/main'

workflow CRAM_MAP_LONG_READS {

    take:
    ch_assemblies           // Channel [meta, assembly]
    ch_crams                // Channel [meta, cram] OR [meta, [cram1, cram2, ..., cram_n]]
    val_cram_chunk_size     // integer: Number of CRAM slices per chunk for mapping

    main:
    //
    // Logic: rolling check of assembly meta objects to detect duplicates
    //
    def val_asm_meta_list = Collections.synchronizedSet(new HashSet())

    ch_assemblies
        .map { meta, _sample ->
            if (!val_asm_meta_list.add(meta)) {
                error("Error: Duplicate meta object found in `ch_assemblies` in CRAM_MAP_LONG_READS: ${meta}")
            }
            meta
        }

    //
    // Logic: check if CRAM files are accompanied by an index
    //        Get indexes, and index those that aren't
    //
    ch_crams_meta_mod = ch_crams
        .transpose()
        .map { meta, cram -> [ meta + [ cramfile: cram ], cram ] }

    ch_cram_raw = ch_crams_meta_mod
        .branch { meta, cram ->
            def cram_file = file(cram, checkIfExists: true)
            def index = cram + ".crai"
            have_index: file(index).exists()
                return [ meta, cram_file, file(index, checkIfExists: true) ]
            no_index: true
                return [ meta, cram_file ]
        }

    //
    // Module: Index CRAM files without indexes
    //
    SAMTOOLS_INDEX(ch_cram_raw.no_index)

    ch_cram_indexed = ch_cram_raw.have_index
        .mix(
            ch_cram_raw.no_index.join(SAMTOOLS_INDEX.out.crai)
        )

    // Module: Process the cram index files to determine how many
    //         chunks to split into for mapping
    //
    CRAMALIGN_GENCRAMCHUNKS(
        ch_cram_indexed,
        val_cram_chunk_size
    )

    //
    // Logic: Count the total number of cram chunks for downstream grouping
    //
    ch_n_cram_chunks = CRAMALIGN_GENCRAMCHUNKS.out.cram_slices
        .map { meta, _cram, _crai, chunkn, _slices ->
            def clean_meta = meta - meta.subMap("cramfile")
            [ clean_meta, chunkn ]
        }
        .transpose()
        .groupTuple(by: 0)
        .map { meta, chunkns ->[ meta, chunkns.size() ] }

    //
    // Module: Extract read groups from CRAM headers
    //
    SAMTOOLS_SPLITHEADER(ch_crams_meta_mod)

    ch_readgroups = SAMTOOLS_SPLITHEADER.out.readgroup
        .map { meta, rg_file ->
            [ meta, rg_file.readLines().collect { line -> line.replaceAll("\t", "\\\\t") } ]
        }

    //
    // Logic: Join reagroups with the CRAM chunks
    //
    ch_cram_rg = ch_readgroups
        .combine(CRAMALIGN_GENCRAMCHUNKS.out.cram_slices.transpose(), by: 0)
        .map { meta, rg, cram, crai, chunkn, slices ->
            def clean_meta = meta - meta.subMap("cramfile")
            [ clean_meta, rg, cram, crai, chunkn, slices ]
        }

    //
    // MODULE: generate minimap2 mmi file
    //
    MINIMAP2_INDEX(ch_assemblies)

    ch_mapping_inputs = ch_cram_rg
        .combine(ch_assemblies, by: 0)
        .combine(MINIMAP2_INDEX.out.index, by: 0)
        .multiMap { meta, rg, cram, crai, chunkn, slices, assembly, index ->
            cram:      [ meta, cram, crai, rg ]
            reference: [ meta, index, assembly ]
            slices:    [ chunkn, slices ]
        }

    CRAMALIGN_MINIMAP2ALIGN(
        ch_mapping_inputs.cram,
        ch_mapping_inputs.reference,
        ch_mapping_inputs.slices
    )

    //
    // Logic: Prepare input for merging bams.
    //        We use the ch_n_cram_chunks to set a groupKey so that
    //        we emit groups downstream ASAP once all bams have been made
    //
    ch_merge_input = CRAMALIGN_MINIMAP2ALIGN.out.bam
        .combine(ch_n_cram_chunks, by: 0)
        .map { meta, bam, n_chunks ->
            def key = groupKey(meta, n_chunks)
            [key, bam]
        }
        .groupTuple(by: 0)
        .map { key, bam -> [key.target, bam] } // Get meta back out of groupKey

    //
    // Subworkflow: merge BAM files and mark duplicates
    //
    BAM_SAMTOOLS_MERGE_MARKDUP(
        ch_merge_input,
        ch_assemblies,
        false
    )

    emit:
    bam               = BAM_SAMTOOLS_MERGE_MARKDUP.out.bam
    bam_index         = BAM_SAMTOOLS_MERGE_MARKDUP.out.bam_index
}
