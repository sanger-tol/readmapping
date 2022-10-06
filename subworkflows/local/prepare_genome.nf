//
// Uncompress and prepare reference genome files
//

include { GUNZIP                  } from '../../modules/nf-core/modules/nf-core/gunzip/main'
include { REMOVE_MASKING          } from '../../modules/local/remove_masking'
include { UNTAR as UNTAR_BWAMEM2  } from '../../modules/nf-core/modules/nf-core/untar/main'
include { BWAMEM2_INDEX           } from '../../modules/nf-core/modules/nf-core/bwamem2/index/main'
include { UNTAR as UNTAR_SAMTOOLS } from '../../modules/nf-core/modules/nf-core/untar/main'
include { SAMTOOLS_FAIDX          } from '../../modules/nf-core/modules/nf-core/samtools/faidx/main'

workflow PREPARE_GENOME {
    take:
    asm         // channel: /path/to/fasta

    main:
    ch_versions = Channel.empty()

    // Uncompress genome fasta file if required
    if (params.fasta.endsWith('.gz')) {
        ch_fasta    = GUNZIP ( asm.map { file -> [ [ id: file.baseName.replaceFirst(/.fa.*/, "") ], file ] } ).gunzip
        ch_versions = ch_versions.mix(GUNZIP.out.versions)
    } else {
        ch_fasta    = asm.map { file -> [ [ id: file.baseName ], file ] }
    }

    // Unmask genome fasta
    REMOVE_MASKING ( ch_fasta )
    ch_versions = ch_versions.mix(REMOVE_MASKING.out.versions)

    // Generate BWA index
    ch_bwamem2_index = Channel.empty()
    if (params.bwamem2_index) {
        bwamem = Channel.fromPath(params.bwamem2_index).combine(ch_fasta).map { bwa, meta, fa -> [ meta, bwa ] }
        if (params.bwamem2_index.endsWith('.tar.gz')) {
            ch_bwamem2_index = UNTAR_BWAMEM2 ( bwamem ).untar
            ch_versions      = ch_versions.mix(UNTAR_BWAMEM2.out.versions)
        } else {
            ch_bwamem2_index = bwamem
        }
    } else {
        ch_bwamem2_index = BWAMEM2_INDEX (REMOVE_MASKING.out.fasta).index
        ch_versions      = ch_versions.mix(BWAMEM2_INDEX.out.versions)
    }

    // Generate Samtools index
    ch_samtools_index = Channel.empty()
    if (params.samtools_index) {
        faidx = Channel.fromPath(params.samtools_index).combine(ch_fasta).map { file, meta, fa -> [ meta, file ] }
        if (params.samtools_index.endsWith('.tar.gz')) {
            ch_samtools_index = UNTAR_SAMTOOLS ( faidx ).untar
            ch_versions       = ch_versions.mix(UNTAR_SAMTOOLS.out.versions)
        } else {
            ch_samtools_index = faidx
        }
    } else {
        ch_samtools_index = SAMTOOLS_FAIDX (REMOVE_MASKING.out.fasta).fai
        ch_versions       = ch_versions.mix(SAMTOOLS_FAIDX.out.versions)
    }

    // Update genome
    ch_asm   = REMOVE_MASKING.out.fasta.map { meta, file -> file }

    emit:
    fasta    = ch_asm                    // path: /path/to/fasta
    bwaidx   = ch_bwamem2_index          // path: [meta, bwamem2/]
    faidx    = ch_samtools_index         // path: [meta, genome.fai]
    versions = ch_versions.ifEmpty(null) // channel: [ versions.yml ]
}
