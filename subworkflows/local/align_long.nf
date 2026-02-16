//
// Align PacBio read files against the genome
//
params.fastx_chunk_size = 10000

// Include local modules and subworkflows
include { SAMTOOLS_ADDREPLACERG                      } from '../../modules/local/samtools_addreplacerg'
include { MERGE_OUTPUT                               } from '../../subworkflows/local/merge_output'

include { PACBIO_PREPROCESS                          } from '../../subworkflows/sanger-tol/pacbio_preprocess/main'
include { PACBIO_PREPROCESS as PACBIO_PREPROCESS_ULI } from '../../subworkflows/sanger-tol/pacbio_preprocess/main'
include { CRAM_MAP_LONG_READS                        } from '../../subworkflows/sanger-tol/cram_map_long_reads'

// Include nf-core modules
include { FASTQC as FASTQC_FILTERED                    } from '../../modules/nf-core/fastqc/main'
include { GAWK                                         } from '../../modules/nf-core/gawk/main'                                                                                                  
include { SAMTOOLS_FASTQ                               } from '../../modules/nf-core/samtools/fastq/main'
include { SAMTOOLS_VIEW as CONVERT_CRAM                } from '../../modules/nf-core/samtools/view/main'

workflow ALIGN_LONG {
    take:
    fasta                          // channel: [ val(meta), /path/to/fasta ]
    reads                          // channel: [ val(meta), /path/to/datafile ]
    val_pacbio_adapter_fasta       // channel: /path/to/pacbio_adapter_fasta for blastn database (produce blast input for hifi_trimmer_processblast)
    val_pacbio_adapter_yaml        // channel: /path/to/pacbio_adapter_yaml for hifitrimmer to process blast output for adapter trimming
    val_pacbio_uli_adapter         // channel: /path/to/pacbio_uli_adapter for lima demultiplexing
    val_pacbio_pbmarkdup           // channel: true/false to run pbmarkdup

    main:
    ch_versions    = channel.empty()
    fastx          = channel.empty()
    mqc_files      = channel.empty()

    if (val_pacbio_adapter_fasta || val_pacbio_adapter_yaml || val_pacbio_uli_adapter || val_pacbio_pbmarkdup) { // pacbio_adapter_fasta, pacbio_adapter_yaml, pacbio_uli_adapter always provided
        ch_reads = reads
            .branch { meta, reads ->
                pacbio: meta.datatype == "pacbio"
                other: true
            }
       // 
        // PREPARE INPUT FOR ADAPTER TRIMMING WITH HIFITRIMMER
        //
        // If adapter fasta provided but not yaml, throw error as yaml is needed for adapter trimming with hifitrimmer
        if ( (val_pacbio_adapter_fasta && !val_pacbio_adapter_yaml) || (!val_pacbio_adapter_fasta && val_pacbio_adapter_yaml) ) { 
            log.error("""
            To trim PacBio adapters, please ensure providing both val_pacbio_adapter_fasta and val_pacbio_adapter_yaml for PacBio adapter trimming.
            To skip trimming, please set both val_pacbio_adapter_fasta and val_pacbio_adapter_yaml to false.
            """) 
        }

        if (val_pacbio_adapter_fasta && val_pacbio_adapter_yaml) {
            ch_yaml_meta = ch_reads.pacbio
                .combine( channel.fromPath(val_pacbio_adapter_yaml, checkIfExists: true) )
                .map { meta, reads, yaml -> [ meta, yaml ] 
                }

            GAWK( ch_yaml_meta, [], false )
            ch_pacbio_read_yaml = ch_reads.pacbio.combine(GAWK.out.output, by: 0)
            adapter_fasta_for_preprocess = [[id:file( val_pacbio_adapter_fasta ).baseName], val_pacbio_adapter_fasta]
        } else {
            ch_pacbio_read_yaml = ch_reads.pacbio.map { meta, reads -> [ meta, reads, [] ] } //PacBio reads with dummy yaml
            adapter_fasta_for_preprocess = false
        }

        //
        // PREPARE INPUT FOR ULI DEMULTIPLEXING WITH LIMA
        //
        // Branch reads by library type (ULI vs non-ULI)
        ch_pacbio_branched = ch_pacbio_read_yaml
                .branch { meta, reads, yaml ->
                uli: meta.library == "uli"
                other: true
            }
        // Preprocess ULI, if ch_uli is empty, this will be skipped
        ch_uli = ch_pacbio_branched.uli
            .multiMap { meta, reads, yaml ->
                reads: [ meta, reads ] 
                yaml: [ meta, yaml ]
            }
        // As ULI is read-file-level, preprocessing has to be called twice for ULI and non-ULI reads separately
        PACBIO_PREPROCESS_ULI( ch_uli.reads, ch_uli.yaml, adapter_fasta_for_preprocess, val_pacbio_uli_adapter, val_pacbio_pbmarkdup )

        // Preprocess non-ULI 
        ch_other = ch_pacbio_branched.other
            .multiMap { meta, reads, yaml ->
                reads: [ meta, reads ] 
                yaml: [ meta, yaml ]
            }

        PACBIO_PREPROCESS( ch_other.reads, ch_other.yaml, adapter_fasta_for_preprocess, [], val_pacbio_pbmarkdup )

        pacbio_fastx = fastx.mix( PACBIO_PREPROCESS.out.trimmed_fastx )
            .mix( PACBIO_PREPROCESS.out.untrimmed_fastx )
            .mix( PACBIO_PREPROCESS_ULI.out.trimmed_fastx )
            .mix( PACBIO_PREPROCESS_ULI.out.untrimmed_fastx )

        // QC for preprocessed fastx files
        untrimmed_bam = PACBIO_PREPROCESS.out.untrimmed_bam.mix(PACBIO_PREPROCESS_ULI.out.untrimmed_bam)
        SAMTOOLS_FASTQ( untrimmed_bam, false )
        FASTQC_FILTERED ( pacbio_fastx.mix( SAMTOOLS_FASTQ.out.other ) )

        mqc_files = mqc_files.mix( FASTQC_FILTERED.out.zip )
            .mix( PACBIO_PREPROCESS_ULI.out.lima_report )
            .mix( PACBIO_PREPROCESS_ULI.out.lima_summary )
            .mix( PACBIO_PREPROCESS_ULI.out.hifitrimmer_bed )
            .mix( PACBIO_PREPROCESS_ULI.out.hifitrimmer_summary )
            .mix( PACBIO_PREPROCESS_ULI.out.pbmarkdup_stat )

        reads_to_cram = untrimmed_bam
            .mix( ch_reads.other )
            .mix( pacbio_fastx )
    } else {
        // if no processing needed at all, prepare CRAM for alignment directly from original reads (both pacbio and non-pacbio reads)
        reads_to_cram = reads
    }

    // readmapping take only 1 FASTA
    CONVERT_CRAM ( reads_to_cram.map{ meta, reads -> [ meta, reads, [] ] }, fasta, [], [] )
    SAMTOOLS_ADDREPLACERG ( CONVERT_CRAM.out.cram )
    ch_versions = ch_versions.mix ( SAMTOOLS_ADDREPLACERG.out.versions )

    ch_reads_cram = SAMTOOLS_ADDREPLACERG.out.cram

    // Prepare input for alignment
    ch_align_input = ch_reads_cram
    .combine( fasta )
    .multiMap { meta, cram, meta_fasta, fasta ->
        cram: [ meta_fasta + meta + [ assembly_id: meta_fasta.id ] , cram ]
        fasta: [ meta_fasta + meta + [ assembly_id: meta_fasta.id ] , fasta ]
    }

    CRAM_MAP_LONG_READS ( ch_align_input.fasta, ch_align_input.cram, params.chunk_size )

    //
    // SUBWORKFLOW: Merge all alignment output by sample name
    //
    ch_sort  = MERGE_OUTPUT ( CRAM_MAP_LONG_READS.out.bam ).bam

    emit:
    bam        = ch_sort                      // channel: [ val(meta), /path/to/bam ]
    mqc_files  = mqc_files                    // channel: [ val(meta), /path/to/fastqc zip]
    versions   = ch_versions                  // channel: [ versions.yml ]
}
