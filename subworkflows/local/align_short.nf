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
        meta, reads_files ->
            cram : reads_files.findAll { file -> file.name.endsWith(".cram") }
                [meta + [from: "cram"], reads_files]
            bam: reads_files.findAll { file -> file.name.endsWith(".bam") }
                [meta + [from: "bam"], reads_files]
            fastx: true
                [meta + [from: "fastx"], reads_files]
    }


    // Convert FASTQ to CRAM only if FASTQ were provided as input
    ch_reads_non_crams = ch_reads.fastx
        .mix ( ch_reads.bam )
        .map { meta, file -> [ meta, file, [] ] }
    CONVERT_CRAM ( ch_reads_non_crams, fasta, [], [] )

    ch_converted_crams = CONVERT_CRAM.out.cram
        .branch { meta, cram ->
            with_rg: meta.from == "bam"
            without_rg: true
        }
    SAMTOOLS_ADDREPLACERG (
        ch_converted_crams.without_rg.map{ meta, cram -> [ meta, cram, [], meta.read_group ] },
        [[],[],[],[]]
    )

    ch_reads_cram = SAMTOOLS_ADDREPLACERG.out.cram
    .mix ( ch_converted_crams.with_rg )
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
