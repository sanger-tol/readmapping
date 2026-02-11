//
// Align Nanopore read files against the genome
//
include { SAMTOOLS_ADDREPLACERG             } from '../../modules/local/samtools_addreplacerg'
include { SAMTOOLS_INDEX                    } from '../../modules/nf-core/samtools/index/main'
include { GENERATE_CRAM_CSV                 } from '../../modules/local/generate_cram_csv'
include { CRAM_MAP_LONG_READS               } from '../../subworkflows/sanger-tol/cram_map_long_reads'
include { SAMTOOLS_VIEW as CONVERT_CRAM     } from '../../modules/nf-core/samtools/view/main'
include { MERGE_OUTPUT                      } from '../../subworkflows/local/merge_output'


workflow ALIGN_ONT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ]
    reads    // channel: [ val(meta), /path/to/datafile ]


    main:
    ch_versions = channel.empty()
    ch_merged_bam   = channel.empty()

    // Convert FASTQ to CRAM
    reads_with_dummy_index = reads.map { meta, file -> [ meta, file, [] ] }
    CONVERT_CRAM ( reads_with_dummy_index, fasta, [], [] )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.cram )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    .set { ch_reads_cram }

    ch_align_input = ch_reads_cram
    .combine( fasta )
    .multiMap { meta, cram, meta_, fasta_file ->
        cram: [ meta_ + meta + [ assembly_id: meta_.id ] , cram ]
        fasta: [ meta_ + meta + [ assembly_id: meta_.id ] , fasta_file ]
    }

    //
    // SUBWORKFLOW: mapping long reads using minimap2 or bwamem2
    //
    CRAM_MAP_LONG_READS ( ch_align_input.fasta, ch_align_input.cram, params.chunk_size )

    //
    // SUBWORKFLOW: Merge all alignment output by specimen
    //
    ch_sort  = MERGE_OUTPUT ( CRAM_MAP_LONG_READS.out.bam ).bam

    emit:
    bam      = ch_sort                       // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
