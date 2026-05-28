//
// Align PacBio read files against the genome
//

// Include local modules and subworkflows
include { MERGE_OUTPUT                               } from '../../subworkflows/local/merge_output'
include { PREPARE_READ_GROUPS                        } from '../../subworkflows/local/prepare_read_groups'

include { PACBIO_PREPROCESS                          } from '../../subworkflows/sanger-tol/pacbio_preprocess/main'
include { PACBIO_PREPROCESS as PACBIO_PREPROCESS_ULI } from '../../subworkflows/sanger-tol/pacbio_preprocess/main'
include { FASTX_MAP_LONG_READS                       } from '../../subworkflows/sanger-tol/fastx_map_long_reads/main'

// Include nf-core modules
include { FASTQC as FASTQC_FILTERED                    } from '../../modules/nf-core/fastqc/main'
include { GAWK as GAWK_MODIFY_YAML_BARCODE             } from '../../modules/nf-core/gawk/main'
include { SAMTOOLS_FASTQ                               } from '../../modules/nf-core/samtools/fastq/main'

workflow ALIGN_LONG {
    take:
    fasta                          // channel: [ val(meta), /path/to/fasta ]
    reads                          // channel: [ val(meta), /path/to/datafile ] only accept FASTQ/BAM
    val_pacbio_adapter_fasta       // channel: /path/to/pacbio_adapter_fasta for blastn database (produce blast input for hifi_trimmer_processblast)
    val_pacbio_adapter_yaml        // channel: /path/to/pacbio_adapter_yaml for hifitrimmer to process blast output for adapter trimming
    val_pacbio_uli_adapter         // channel: /path/to/pacbio_uli_adapter for lima demultiplexing

    main:
    fastx          = channel.empty()
    mqc_files      = channel.empty()

    //
    // PRESERVE READ GROUP INFORMATION
    //
    PREPARE_READ_GROUPS(reads, 'long')
    ch_read_rg = PREPARE_READ_GROUPS.out.reads
    ch_read_rg_branch = ch_read_rg.branch { _meta, read_files ->
        bam: read_files.name.endsWith("bam")
        fastq: true
    }

    //
    // PACBIO READ PREPROCESSING
    //
    if (val_pacbio_adapter_fasta || val_pacbio_adapter_yaml || val_pacbio_uli_adapter) { // pacbio_adapter_fasta, pacbio_adapter_yaml, pacbio_uli_adapter always provided
        ch_reads = ch_read_rg
            .branch { meta, read_files ->
                pacbio: meta.datatype == "pacbio"
                // non pacbio includes ONT and pacbio clr
                non_pacbio_bam: read_files.name.endsWith(".bam")
                non_pacbio_fastx: true
            }
        //
        // PREPARE INPUT FOR ADAPTER TRIMMING WITH HIFITRIMMER
        //
        // If adapter fasta provided but not yaml, throw error as yaml is needed for adapter trimming with hifitrimmer
        if ( (val_pacbio_adapter_fasta && !val_pacbio_adapter_yaml) || (!val_pacbio_adapter_fasta && val_pacbio_adapter_yaml) ) {
            log.error("""
            Adapter trimming configuration is invalid. Please provide BOTH parameters: pacbio_adapter_fasta & pacbio_adapter_yaml.
            Or set BOTH to false to disable adapter trimming for PacBio reads.
            """)
        }

        if (val_pacbio_adapter_fasta && val_pacbio_adapter_yaml) {
            ch_yaml_meta = ch_reads.pacbio
                .combine( channel.fromPath(val_pacbio_adapter_yaml, checkIfExists: true) )
                .map{ meta, _reads, yaml -> [ meta, yaml ]}
                .branch { meta, yaml ->
                    has_barcode: meta.barcode != null && !meta.barcode.isEmpty()
                    no_barcode: true
                }
            GAWK_MODIFY_YAML_BARCODE( ch_yaml_meta.has_barcode, [], false )
            ch_yml_barcoded = GAWK_MODIFY_YAML_BARCODE.out.output.mix( ch_yaml_meta.no_barcode )
            ch_pacbio_read_yaml = ch_reads.pacbio.combine(ch_yml_barcoded, by: 0)
            adapter_fasta_for_preprocess = [[id:file( val_pacbio_adapter_fasta ).baseName], val_pacbio_adapter_fasta]
        } else {
            ch_pacbio_read_yaml = ch_reads.pacbio.map { meta, read_files -> [ meta, read_files, [] ] } //PacBio reads with dummy yaml
            adapter_fasta_for_preprocess = false
        }

        //
        // PREPARE INPUT FOR ULI DEMULTIPLEXING WITH LIMA
        //
        // Branch reads by library type (ULI vs non-ULI)
        ch_pacbio_branched = ch_pacbio_read_yaml
                .branch { meta, _reads, _yaml ->
                uli: meta.library == "uli"
                other: true
            }
        // Preprocess ULI, if ch_uli is empty, this will be skipped
        ch_uli = ch_pacbio_branched.uli
            .multiMap { meta, read_files, yaml ->
                reads: [ meta, read_files ]
                yaml: [ meta, yaml ]
            }
        // As ULI is read-file-level, preprocessing has to be called twice for ULI and non-ULI reads separately
        PACBIO_PREPROCESS_ULI( ch_uli.reads, ch_uli.yaml, adapter_fasta_for_preprocess, val_pacbio_uli_adapter, true )

        // Preprocess non-ULI
        ch_other = ch_pacbio_branched.other
            .multiMap { meta, read_files, yaml ->
                reads: [ meta, read_files ]
                yaml: [ meta, yaml ]
            }

        PACBIO_PREPROCESS( ch_other.reads, ch_other.yaml, adapter_fasta_for_preprocess, [], false ) // No pbmarkdup for non-ULI

        pacbio_fastx = fastx.mix( PACBIO_PREPROCESS.out.trimmed_fastx )
            .mix( PACBIO_PREPROCESS.out.untrimmed_fastx )
            .mix( PACBIO_PREPROCESS_ULI.out.trimmed_fastx )
            .mix( PACBIO_PREPROCESS_ULI.out.untrimmed_fastx )

        // QC for preprocessed fastx files
        untrimmed_bam = PACBIO_PREPROCESS.out.untrimmed_bam.mix(PACBIO_PREPROCESS_ULI.out.untrimmed_bam)
        FASTQC_FILTERED ( pacbio_fastx.mix( untrimmed_bam ) )

        mqc_files = mqc_files.mix( FASTQC_FILTERED.out.zip )
            .mix( PACBIO_PREPROCESS_ULI.out.lima_report )
            .mix( PACBIO_PREPROCESS_ULI.out.lima_summary )
            .mix( PACBIO_PREPROCESS_ULI.out.hifitrimmer_bed )
            .mix( PACBIO_PREPROCESS_ULI.out.hifitrimmer_summary )
            .mix( PACBIO_PREPROCESS_ULI.out.pbmarkdup_stat )

        bam_to_fastx = untrimmed_bam.mix( ch_reads.non_pacbio_bam )
        fastx = pacbio_fastx.mix( ch_reads.non_pacbio_fastx )
    } else {
        // if no processing needed at all, prepare CRAM for alignment directly from original reads (both pacbio and non-pacbio reads)
        bam_to_fastx = ch_read_rg_branch.bam
        fastx = ch_read_rg_branch.fastq
    }
    // readmapping take only 1 FASTA as reference
    SAMTOOLS_FASTQ ( bam_to_fastx, false )
    ch_reads_fastx = SAMTOOLS_FASTQ.out.other.mix( fastx )
    .map{ meta, fastx_file -> [ meta + [ reads_size: fastx_file.size() ] , fastx_file ] }

    // Prepare input for alignment
    ch_align_input = ch_reads_fastx
    .combine( fasta )
    .multiMap { meta, fastx_files, meta_fasta, fasta_file ->
        cram: [ meta_fasta + meta + [ assembly_id: meta_fasta.id ] , fastx_files ]
        fasta: [ meta_fasta + meta + [ assembly_id: meta_fasta.id ] , fasta_file ]
    }

    FASTX_MAP_LONG_READS ( ch_align_input.fasta, ch_align_input.cram, params.long_reads_map_chunk_size, true )

    //
    // SUBWORKFLOW: Merge all alignment outputs by specimen
    //
    ch_sort  = MERGE_OUTPUT ( FASTX_MAP_LONG_READS.out.bam ).bam

    emit:
    bam        = ch_sort                      // channel: [ val(meta), /path/to/bam ]
    mqc_files  = mqc_files                    // channel: [ val(meta), /path/to/fastqc zip]
}
