//
// Align short read (HiC and Illumina) data against the genome
//

include { CRAM_MAP_ILLUMINA_HIC as CRAM_MAP_ILLUMINA } from '../../subworkflows/sanger-tol/cram_map_illumina_hic'
include { MERGE_OUTPUT                               } from '../../subworkflows/local/merge_output'
include { SAMTOOLS_ADDREPLACERG                      } from '../../modules/local/samtools_addreplacerg'
include { SAMTOOLS_SORMADUP as CONVERT_CRAM          } from '../../modules/local/samtools_sormadup'

workflow ALIGN_SHORT {
    take:
    fasta    // channel: [ val(meta), /path/to/fasta ] reference_tuple
    index    // channel: [ val(meta), /path/to/bwamem2/ ]
    reads    // channel: [ val(meta), /path/to/datafile ] hic_reads_path


    main:
    ch_versions = channel.empty()
    ch_merged_bam   = channel.empty()

    // Check file types and branch
    reads
    .branch {
        meta, reads ->
            fastq : reads.findAll { it.getName().toLowerCase() =~ /.*f.*\.gz/ }
            cram : true
    }
    .set { ch_reads }


    // Convert FASTQ to CRAM only if FASTQ were provided as input
    CONVERT_CRAM ( ch_reads.fastq, fasta )
    ch_versions = ch_versions.mix ( CONVERT_CRAM.out.versions )

    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.bam )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    SAMTOOLS_ADDREPLACERG.out.cram
    .mix ( ch_reads.cram )
    .set { ch_reads_cram }

    ch_illumina = ch_reads_cram
    .combine(fasta)
    .multiMap { meta, cram, meta_, fasta ->
        cram: [ meta_ + meta + [ assembly_id: meta_.id ] , cram ]
        fasta: [ meta_ + meta + [ assembly_id: meta_.id ] , fasta ]
    }

    CRAM_MAP_ILLUMINA( ch_illumina.fasta, ch_illumina.cram, params.short_aligner, params.chunk_size )
    //
    // SUBWORKFLOW: Merge all alignment output by sample name
    //
    MERGE_OUTPUT( CRAM_MAP_ILLUMINA.out.bam )
    ch_sort = MERGE_OUTPUT.out.bam

    emit:
    bam      = MERGE_OUTPUT.out.bam     // channel: [ val(meta), /path/to/bam ]
    versions = ch_versions                   // channel: [ versions.yml ]
}
