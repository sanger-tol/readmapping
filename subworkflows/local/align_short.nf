//
// Align short read (HiC and Illumina) data against the genome
//

include { CRAM_MAP_ILLUMINA_HIC as CRAM_MAP_ILLUMINA } from '../../subworkflows/sanger-tol/cram_map_illumina_hic'
include { MERGE_OUTPUT                               } from '../../subworkflows/local/merge_output'
include { SAMTOOLS_ADDREPLACERG                      } from '../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_VIEW as CONVERT_CRAM              } from '../../modules/nf-core/samtools/view/main'

workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ] reference_tuple
    reads    // channel: [ val(meta), /path/to/datafile ] hic_reads_path


    main:
    // Check file types and branch
    ch_reads = reads
    .branch {
        _meta, reads_files ->
            fastq : reads_files.findAll { file -> file.getName().toLowerCase() =~ /.*f.*\.gz/ }
            cram : true
    }


    // Convert FASTQ to CRAM only if FASTQ were provided as input
    reads_with_dummy_index = ch_reads.fastq.map { meta, file -> [ meta, file, [] ] }
    CONVERT_CRAM ( reads_with_dummy_index, fasta, [], [] )

    SAMTOOLS_ADDREPLACERG (
        CONVERT_CRAM.out.cram.map{ meta, cram -> [ meta, cram, [], meta.read_group ] },
        [[],[],[],[]]
    )

    ch_reads_cram = SAMTOOLS_ADDREPLACERG.out.cram
    .mix ( ch_reads.cram )
    .map{ meta, cram_file -> [ meta + [ reads_size: cram_file.size() ] , cram_file ] }

    ch_illumina = ch_reads_cram
    .combine(fasta)
    .multiMap { meta, cram, meta_, fasta_file ->
        cram: [ meta_ + meta + [ assembly_id: meta_.id ] , cram ]
        fasta: [ meta_ + meta + [ assembly_id: meta_.id ] , fasta_file ]
    }

    CRAM_MAP_ILLUMINA( ch_illumina.fasta, ch_illumina.cram, params.short_aligner, params.short_reads_map_chunk_size )
    //
    // SUBWORKFLOW: Merge all alignment outputs by specimen
    //
    MERGE_OUTPUT( CRAM_MAP_ILLUMINA.out.bam )

    emit:
    bam      = MERGE_OUTPUT.out.bam     // channel: [ val(meta), /path/to/bam ]
}
