//
// Align short read (HiC and Illumina) data against the genome
//

include { CRAM_MAP_ILLUMINA_HIC as CRAM_MAP_SHORT_READS } from '../../subworkflows/sanger-tol/cram_map_illumina_hic'
include { MERGE_OUTPUT                                  } from '../../subworkflows/local/merge_output'
include { PREPARE_READ_GROUPS                           } from '../../subworkflows/local/prepare_read_groups'
include { SAMTOOLS_ADDREPLACERG                         } from '../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_VIEW as CONVERT_CRAM                 } from '../../modules/nf-core/samtools/view/main'

workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ] reference_tuple
    reads    // channel: [ val(meta), /path/to/datafile ] hic_reads_path


    main:
    //
    // SUBWORKFLOW: Preserve read-group information from optional extra_header metadata
    //
    PREPARE_READ_GROUPS(reads, 'short')
    reads_with_rg = PREPARE_READ_GROUPS.out.reads

    //
    // LOGIC: Convert FASTQ to CRAM and add RG information if needed
    //
    // Check file types and branch
    ch_reads = reads_with_rg.branch { _meta, read_files ->
        cram: read_files.name.endsWith(".cram")
        non_cram: true
    }

    // Convert FASTQ to CRAM only if FASTQ were provided as input
    ch_reads_non_crams = ch_reads.non_cram.map { meta, file -> [ meta, file, [] ] }

    fasta_dummy_idx = fasta.map { meta, fasta_file -> [ meta, fasta_file, [] ] }
    CONVERT_CRAM ( ch_reads_non_crams, fasta_dummy_idx, [[],[]], [[],[]], [[],[]], "" )

    // Add read group information to CRAMs if not already present, and merge with CRAMs that already have RG information
    ch_crams_to_addrg = CONVERT_CRAM.out.cram
        .mix ( ch_reads.cram )
        .branch { meta, _cram ->
            replace_rg: meta.replace_rg == true
            not_replace_rg: true
        }
    SAMTOOLS_ADDREPLACERG (
        ch_crams_to_addrg.replace_rg.map{ meta, cram -> [ meta, cram, [], [] ] }, // empty value for RG as the modules will use meta.read_group instead (see conf/modules.config)
        [[],[],[],[]]
    )

    //
    // SUBWORKFLOW: Align short reads
    //
    ch_cram_to_map = SAMTOOLS_ADDREPLACERG.out.cram
        .mix ( ch_crams_to_addrg.not_replace_rg )
        .map{ meta, cram_file -> [ meta + [ reads_size: cram_file.size() ] , cram_file ] }
        .combine(fasta)
        .multiMap { meta, cram, meta_, fasta_file ->
            cram: [ meta_ + meta + [ assembly_id: meta_.id ] , cram ]
            fasta: [ meta_ + meta + [ assembly_id: meta_.id ] , fasta_file ]
        }

    CRAM_MAP_SHORT_READS( ch_cram_to_map.fasta, ch_cram_to_map.cram, params.short_aligner, params.short_reads_map_chunk_size )
    //
    // SUBWORKFLOW: Merge all alignment outputs by specimen
    //
    MERGE_OUTPUT( CRAM_MAP_SHORT_READS.out.bam )

    emit:
    bam      = MERGE_OUTPUT.out.bam     // channel: [ val(meta), /path/to/bam ]
}
