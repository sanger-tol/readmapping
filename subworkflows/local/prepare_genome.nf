//
// Uncompress and prepare reference genome files
//

include { GUNZIP                  } from '../../modules/nf-core/modules/gunzip/main'
include { REMOVE_MASKING          } from '../../modules/local/custom/remove_masking'
include { UNTAR as UNTAR_BWAMEM2  } from '../../modules/nf-core/modules/untar/main'
include { BWAMEM2_INDEX           } from '../../modules/local/bwamem2/index'
include { UNTAR as UNTAR_MINIMAP2 } from '../../modules/nf-core/modules/untar/main'
include { MINIMAP2_INDEX          } from '../../modules/nf-core/modules/minimap2/index/main'
include { UNTAR as UNTAR_SAMTOOLS } from '../../modules/nf-core/modules/untar/main'
include { SAMTOOLS_FAIDX          } from '../../modules/local/samtools/faidx'

workflow PREPARE_GENOME {
    main:
    ch_versions = Channel.empty()

    // Uncompress genome fasta file if required
    if (params.fasta.endsWith('.gz')) {
        ch_fasta    = GUNZIP ( [ [:], params.fasta ] ).gunzip.map { it[1] }
        ch_versions = ch_versions.mix(GUNZIP.out.versions)
    } else {
        ch_fasta = file(params.fasta)
    }

    // Unmask genome fasta
    REMOVE_MASKING ( ch_fasta )
    ch_versions = ch_versions.mix(REMOVE_MASKING.out.versions)

    // Generate BWA index
    ch_bwamem2_index = Channel.empty()
    if (params.bwamem2_index) {
        if (params.bwamem2_index.endsWith('.tar.gz')) {
            ch_bwamem2_index = UNTAR_BWAMEM2 (params.bwamem2_index).untar
            ch_versions      = ch_versions.mix(UNTAR_BWAMEM2.out.versions)
        } else {
            ch_bwamem2_index = file(params.bwamem2_index)
        }
    } else {
        ch_bwamem2_index = BWAMEM2_INDEX (REMOVE_MASKING.out.fasta).index
        ch_versions      = ch_versions.mix(BWAMEM2_INDEX.out.versions)
    }

    // Generate Minimap2 index
    ch_minimap2_index = Channel.empty()
    if (params.minimap2_index) {
        if (params.minimap2_index.endsWith('.tar.gz')) {
            ch_minimap2_index = UNTAR_MINIMAP2 (params.minimap2_index).untar
            ch_versions       = ch_versions.mix(UNTAR_MINIMAP2.out.versions)
        } else {
             ch_minimap2_index = file(params.minimap2_index)
        }
    } else {
        ch_minimap2_index = MINIMAP2_INDEX (REMOVE_MASKING.out.fasta).index
        ch_versions       = ch_versions.mix(MINIMAP2_INDEX.out.versions)
    }

    // Generate Samtools index
    ch_samtools_index = Channel.empty()
    if (params.samtools_index) {
        if (params.samtools_index.endsWith('.tar.gz')) {
            ch_samtools_index = UNTAR_SAMTOOLS (params.samtools_index).untar
            ch_versions       = ch_versions.mix(UNTAR_SAMTOOLS.out.versions)
        } else {
            ch_samtools_index = file(params.samtools_index)
        }
    } else {
        ch_samtools_index = SAMTOOLS_FAIDX (REMOVE_MASKING.out.fasta).fai
        ch_versions       = ch_versions.mix(SAMTOOLS_FAIDX.out.versions)
    }

    emit:
    fasta    = REMOVE_MASKING.out.fasta  // path: genome.unmasked.fasta
    bwaidx   = ch_bwamem2_index          // path: bwamem2/index/
    minidx   = ch_minimap2_index         // path: minimap2/index/
    faidx    = ch_samtools_index         // path: samtools/faidx/

    versions = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}
