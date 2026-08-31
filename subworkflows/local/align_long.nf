//
// Align long read files (ONT and PacBio) against the genome
//

// Local subworkflows
include { MERGE_OUTPUT                               } from '../../subworkflows/local/merge_output'

// sanger-tol subworkflows
include { CRAM_MAP_LONG_READS                        } from '../../subworkflows/sanger-tol/cram_map_long_reads/main'
include { PACBIO_PREPROCESS                          } from '../../subworkflows/sanger-tol/pacbio_preprocess/main'
include { FASTX_MAP_LONG_READS                       } from '../../subworkflows/sanger-tol/fastx_map_long_reads/main'

// nf-core modules
include { GAWK as GAWK_MODIFY_YAML_BARCODE           } from '../../modules/nf-core/gawk/main'
include { SAMTOOLS_ADDREPLACERG                      } from '../../modules/nf-core/samtools/addreplacerg/main'
include { SAMTOOLS_SPLITHEADER                       } from '../../modules/nf-core/samtools/splitheader/main'
include { SAMTOOLS_VIEW as CONVERT_CRAM              } from '../../modules/nf-core/samtools/view/main'


workflow ALIGN_LONG {

    take:
    fasta                          // channel: [ val(meta), /path/to/fasta ]
    reads                          // channel: [ val(meta), /path/to/datafile ] (BAM or FASTQ)
    val_pacbio_adapter             // val: BLAST DB path for HiFi-Trimmer adapter detection
    val_pacbio_adapter_yaml        // val: YAML path for HiFi-Trimmer adapter processing
    val_pacbio_uli_adapter         // val: adapter path for LIMA ULI demultiplexing

    main:
    ch_mqc_files = channel.empty()

    //
    // Validate adapter/yaml pairing up front (both required for HiFi-Trimmer)
    //
    if ((val_pacbio_adapter && !val_pacbio_adapter_yaml) || (!val_pacbio_adapter && val_pacbio_adapter_yaml)) {
        log.error("""
        Adapter trimming configuration is invalid. Please provide BOTH parameters: pacbio_adapter & pacbio_adapter_yaml,
        or set BOTH to false to disable adapter trimming for PacBio reads.
        """)
    }

    //
    // PacBio preprocessing (adapter trimming, ULI demultiplexing, dedup, pimms/amplified)
    // Always executed; empty channels propagate harmlessly when no PacBio data is present.
    //
    ch_reads_by_datatype = reads.branch { meta, read_files ->
        pacbio:           meta.datatype == 'pacbio'
        non_pacbio_bam:   read_files.name.endsWith('.bam')  // ONT / PacBio CLR BAM
        non_pacbio_fastx: true                              // ONT / PacBio CLR FASTQ
    }

    //
    // Prepare per-sample YAML for HiFi-Trimmer (with barcode substitution if needed)
    //
    if (val_pacbio_adapter && val_pacbio_adapter_yaml) {
        ch_yaml_by_barcode = ch_reads_by_datatype.pacbio
            .combine(channel.fromPath(val_pacbio_adapter_yaml, checkIfExists: true))
            .map { meta, _reads, yaml -> [ meta, yaml ] }
            .branch { meta, _yaml ->
                has_barcode: meta.barcode != null && !meta.barcode.isEmpty()
                no_barcode:  true
            }

        GAWK_MODIFY_YAML_BARCODE(ch_yaml_by_barcode.has_barcode, [], false)

        ch_pacbio_read_yaml = ch_reads_by_datatype.pacbio.combine(
            GAWK_MODIFY_YAML_BARCODE.out.output.mix(ch_yaml_by_barcode.no_barcode),
            by: 0
        )
        adapter_fasta = val_pacbio_adapter
    } else {
        // No hifi-trimmer adapters requested; attach an empty yaml placeholder
        ch_pacbio_read_yaml = ch_reads_by_datatype.pacbio
            .map { meta, read_files -> [ meta, read_files, [] ] }
        adapter_fasta = false
    }

    //
    // PACBIO_PREPROCESS expects [meta, reads, lima_adapter, run_pbmarkdup, adapter_yaml].
    // ULI uses the global adapter, PiMmS uses its per-sample adapter, amplified reads
    // use pbmarkdup without LIMA, and standard HiFi reads use neither.
    ch_pacbio_preprocess = ch_pacbio_read_yaml.map { meta, read_files, yaml ->
        def library = meta.library ?: ''
        def lima_adapter = library == 'uli' ? val_pacbio_uli_adapter
            : library == 'pimms' && meta.adapter_file ? file(meta.adapter_file)
            : false
        def run_pbmarkdup = library in ['uli', 'pimms', 'amplified']
        [ meta, read_files, lima_adapter, run_pbmarkdup, yaml ]
    }

    PACBIO_PREPROCESS(ch_pacbio_preprocess, adapter_fasta)

    //
    // Aggregate preprocessing outputs
    //
    trimmed_cram  = PACBIO_PREPROCESS.out.trimmed_cram
    untrimmed_bam = PACBIO_PREPROCESS.out.untrimmed_bam  // includes ULI/pimms/amplified via untrimmed_bam emit

    bam_to_cram = untrimmed_bam.mix(ch_reads_by_datatype.non_pacbio_bam)
    fastx       = PACBIO_PREPROCESS.out.untrimmed_fastx
        .mix(PACBIO_PREPROCESS.out.trimmed_fastq)
        .mix(ch_reads_by_datatype.non_pacbio_fastx)

    ch_mqc_files = ch_mqc_files.mix(
        PACBIO_PREPROCESS.out.lima_report,
        PACBIO_PREPROCESS.out.lima_summary,
        PACBIO_PREPROCESS.out.hifitrimmer_bed,
        PACBIO_PREPROCESS.out.hifitrimmer_summary,
        PACBIO_PREPROCESS.out.pbmarkdup_stats,
    )

    //
    // Handle read group and PG lines
    //

    // FASTQ path: build the samtools-style RG arg from the meta.read_group string
    // add_rg=true forces this record through SAMTOOLS_ADDREPLACERG, in case it is converted to CRAM.
    ch_fastq_rg = fastx.map { meta, read_files -> [ meta + [ read_group: "-y -R $meta.read_group", add_rg: true ], read_files ] }

    //
    // Convert BAM inputs to CRAM (readmapping expects a single FASTA reference)
    //
    CONVERT_CRAM(
        bam_to_cram.map { meta, bam       -> [ meta, bam,        [] ] },
        fasta      .map { meta, fasta_file -> [ meta, fasta_file, [] ] },
        [[], []], [[], []], ''
    )
    ch_reads_cram = CONVERT_CRAM.out.cram.mix(trimmed_cram)

    SAMTOOLS_SPLITHEADER(ch_reads_cram)
    ch_cram_rg = SAMTOOLS_SPLITHEADER.out.readgroup
        .join(ch_reads_cram, by: 0)
        .map { meta, rg_file, bam ->
            def rglines = file(rg_file).readLines()
            // Format for samtools addreplacerg: '@RG\t...' quoted, joined by ' -r ' so the module's
            // "-r ${read_group}" expansion yields "-r '@RG\t...' -r '@RG\t...'".
            def rg_args = rglines
                ? rglines.collect { line ->
                    def with_sm = line.contains('SM:') ? line
                                : meta.sample     ? "${line}\tSM:${meta.sample}"
                                                  : "${line}\tSM:${meta.id}"
                    "'${with_sm.replaceAll('\t', '\\\\t')}'"
                }.join(' -r ')
                : "$meta.read_group"
            // add_rg=true when the BAM header lacked @RG lines, or none of them carried an SM tag
            [ meta + [ read_group: rg_args, add_rg: !rglines.any { it.contains('SM:') } ], bam ]
        }

    ch_reads_cram_by_rg = ch_cram_rg.branch { meta, _cram ->
        add_rg:    meta.add_rg
        no_add_rg: true
    }

    SAMTOOLS_ADDREPLACERG(
        ch_reads_cram_by_rg.add_rg.map { meta, cram -> [ meta, cram, [], meta.read_group ] },
        [[], [], [], []]
    )

    pg_lines = SAMTOOLS_SPLITHEADER.out.programs
        .map { meta, file -> [ meta, file.readLines() ] }

    //
    // FASTX alignment path
    //
    ch_align_fastx = ch_fastq_rg
        .map { meta, fastx_file -> [ meta + [ reads_size: fastx_file.size() ], fastx_file ] }
        .combine(fasta)
        .multiMap { meta, fastx_file, meta_asm, fasta_file ->
            def meta_out = meta_asm + meta + [ assembly_id: meta_asm.id ]
            fastx: [ meta_out, fastx_file ]
            fasta: [ meta_out, fasta_file ]
        }

    FASTX_MAP_LONG_READS(
        ch_align_fastx.fasta,
        ch_align_fastx.fastx,
        params.long_reads_map_chunk_size,
        true,
        pg_lines
    )

    //
    // CRAM alignment path: re-header CRAMs whose source BAM had no @RG lines
    //

    ch_align_cram = SAMTOOLS_ADDREPLACERG.out.cram
        .mix(ch_reads_cram_by_rg.no_add_rg)
        .map { meta, cram -> [ meta - meta.subMap('add_rg'), cram ] }
        .combine(fasta)
        .multiMap { meta, cram, meta_asm, fasta_file ->
            // meta must match between cram and fasta inputs for join() downstream
            def meta_out = meta_asm + meta + [ assembly_id: meta_asm.id, reads_size: cram.size() ]
            cram:  [ meta_out, cram ]
            fasta: [ meta_out, fasta_file ]
        }

    CRAM_MAP_LONG_READS(
        ch_align_cram.fasta,
        ch_align_cram.cram,
        params.long_reads_map_chunk_size,
    )

    //
    // Merge alignment outputs by specimen
    //
    ch_aligned_bam = CRAM_MAP_LONG_READS.out.bam.mix(FASTX_MAP_LONG_READS.out.bam)
    ch_sort        = MERGE_OUTPUT(ch_aligned_bam).bam

    emit:
    bam       = ch_sort      // channel: [ val(meta), /path/to/bam ]
    mqc_files = ch_mqc_files // channel: [ val(meta), /path/to/mqc_file ]
}
