include { BLAST_BLASTN                         } from '../../../modules/sanger-tol/blast/blastn/main'
include { BLAST_MAKEBLASTDB                    } from '../../../modules/nf-core/blast/makeblastdb/main'
include { HIFITRIMMER_PROCESSBLAST             } from '../../../modules/nf-core/hifitrimmer/processblast/main'
include { HIFITRIMMER_TRIM                     } from '../../../modules/nf-core/hifitrimmer/trim/main'
include { LIMA                                 } from '../../../modules/nf-core/lima/main'
include { PBMARKDUP                            } from '../../../modules/nf-core/pbmarkdup/main'
include { UNTAR                                } from '../../../modules/nf-core/untar/main'

workflow PACBIO_PREPROCESS {

    take:
    ch_reads          // Channel [meta, reads, lima_adapter, run_pbmarkdup, adapter_yaml]
    val_hifi_adapter  // Path to Hifi adapter DB or Hifi adapter fasta to make database for blastn

    main:
    ch_reads_branch = ch_reads.branch { meta, reads, lima_adapter, run_pbmarkdup, adapter_yaml ->
        lima: lima_adapter
            return [ meta + [_run_pbmarkdup: run_pbmarkdup, _adapter_yaml: adapter_yaml], reads, lima_adapter ]
        no_lima: true
            return [ meta + [_adapter_yaml: adapter_yaml], reads, run_pbmarkdup ]
    }

    ch_lima_input = ch_reads_branch.lima
        .multiMap { meta, reads, adapter ->
            reads:    [ meta, reads ]
            adapters: adapter
        }

    // args for LIMA should be passed to config file based on libary type
    // For ULI: --hifi-preset 'SYMMETRIC' (For TOL setting, we have one ULI adapter, whose preset is SYMMETRIC)
    // For PiMms: --peek-guess --hifi-preset ${adapter_preset} --split-named"
    LIMA(ch_lima_input.reads, ch_lima_input.adapters)
    lima_reports = LIMA.out.report.map { meta, report -> [ meta - meta.subMap('_run_pbmarkdup', '_adapter_yaml'), report ] }
    lima_summary = LIMA.out.summary.map { meta, summary -> [ meta - meta.subMap('_run_pbmarkdup', '_adapter_yaml'), summary ] }
    ch_post_lima = LIMA.out.bam
        .mix(LIMA.out.fastq)
        .mix(LIMA.out.fasta)
        .mix(LIMA.out.fastqgz)
        .mix(LIMA.out.fastagz)
        .map { meta, reads -> [ meta - meta.subMap('_run_pbmarkdup'), reads, meta._run_pbmarkdup ] }

    ch_pbmarkdup_branch = ch_reads_branch.no_lima
        .mix(ch_post_lima)
        .branch { meta, reads, run_pbmarkdup ->
            markdup: run_pbmarkdup
                return [ meta, reads ]
            no_markdup: true
                return [ meta, reads ]
        }

    PBMARKDUP(ch_pbmarkdup_branch.markdup)
    pbmarkdup_stats = PBMARKDUP.out.log
        .map { meta, log -> [ meta - meta.subMap('_adapter_yaml'), log ] }

    //
    // TRIMMING WITH HIFITRIMMER
    //
    hifitrimmer_summary = channel.empty()
    hifitrimmer_bed     = channel.empty()
    trimmed_bam         = channel.empty()
    trimmed_cram        = channel.empty()
    trimmed_sam         = channel.empty()
    trimmed_fasta       = channel.empty()
    trimmed_fastq       = channel.empty()
    ch_hifitrimmer_input = ch_pbmarkdup_branch.no_markdup.mix(PBMARKDUP.out.markduped)

    if ( val_hifi_adapter ) {

        // Split on whether this record carries an adapter YAML (rides in meta._adapter_yaml)
        ch_hifitrimmer_branch = ch_hifitrimmer_input.branch { meta, reads ->
            trim:      meta._adapter_yaml
            skip_trim: true
        }

        ch_input_skip_trim = ch_hifitrimmer_branch.skip_trim
            .map { meta, reads -> [ meta - meta.subMap('_adapter_yaml'), reads ] }

        ch_input_skip_trim
            .subscribe { _meta, reads ->
                log.warn "No adapter YAML provided, skipping adapter trimming step for: ${reads}"
            }

        ch_input_to_trim = ch_hifitrimmer_branch.trim
            .map { meta, reads -> [ meta - meta.subMap('_adapter_yaml'), reads ] }

        adapter_fasta_ch = channel.of([ [id: file(val_hifi_adapter).baseName], file(val_hifi_adapter) ])
        if ( val_hifi_adapter.endsWith('.tar.gz') ) {
            UNTAR( adapter_fasta_ch )
            adapter_db = UNTAR.out.untar
        } else {
            BLAST_MAKEBLASTDB( adapter_fasta_ch, [] )
            adapter_db = BLAST_MAKEBLASTDB.out.db
        }

        BLAST_BLASTN ( ch_input_to_trim, adapter_db.collect(), [],[],[] )

        // Recover each sample's YAML from meta._adapter_yaml alongside its blastn output
        ch_input_processblast = BLAST_BLASTN.out.txtgz
            .join(ch_hifitrimmer_branch.trim.map { meta, reads -> [ meta - meta.subMap('_adapter_yaml'), meta._adapter_yaml ] }, by: 0)
            .multiMap { meta, blastn, yaml ->
                blastn: [ meta, blastn ]
                yaml:   [ meta, yaml ]
            }

        HIFITRIMMER_PROCESSBLAST ( ch_input_processblast.blastn, ch_input_processblast.yaml )

        hifitrimmer_summary = hifitrimmer_summary.mix ( HIFITRIMMER_PROCESSBLAST.out.summary )
        hifitrimmer_bed     = hifitrimmer_bed.mix ( HIFITRIMMER_PROCESSBLAST.out.bed )

        ch_input_filterbam = ch_input_to_trim.combine( HIFITRIMMER_PROCESSBLAST.out.bed, by: 0 )
        HIFITRIMMER_TRIM ( ch_input_filterbam )

        trimmed_bam   = trimmed_bam.mix( HIFITRIMMER_TRIM.out.bam )
        trimmed_cram  = trimmed_cram.mix( HIFITRIMMER_TRIM.out.cram )
        trimmed_sam   = trimmed_sam.mix( HIFITRIMMER_TRIM.out.sam )
        trimmed_fasta = trimmed_fasta.mix( HIFITRIMMER_TRIM.out.fasta )
        trimmed_fastq = trimmed_fastq.mix( HIFITRIMMER_TRIM.out.fastq )
    } else {
        log.warn "No adapter DB provided, skipping adapter trimming"
        ch_input_skip_trim = ch_hifitrimmer_input.map { meta, reads -> [ meta - meta.subMap('_adapter_yaml'), reads ] }
    }

    ch_input_skip_trim_branch = ch_input_skip_trim
        .branch { meta, reads ->
            bam: reads.name.endsWith('.bam')
                return [ meta, reads ]
            fastx: true
                return [ meta, reads ]
        }

    emit:
    untrimmed_fastx     = ch_input_skip_trim_branch.fastx   // [meta, fastx] untrimmed reads in FASTA/FASTQ format
    untrimmed_bam       = ch_input_skip_trim_branch.bam     // [meta, bam] untrimmed reads in BAM format
    trimmed_cram        = trimmed_cram                      // [meta, CRAM] preprocessed reads in CRAM format
    trimmed_bam         = trimmed_bam                       // [meta, BAM] preprocessed reads in BAM format
    trimmed_sam         = trimmed_sam                       // [meta, SAM] preprocessed reads in SAM format
    trimmed_fasta       = trimmed_fasta                     // [meta, FASTA] preprocessed reads in FASTA format
    trimmed_fastq       = trimmed_fastq                     // [meta, FASTQ] preprocessed reads in FASTQ format
    lima_report         = lima_reports                      // [meta, report]
    lima_summary        = lima_summary                      // [meta, summary]
    hifitrimmer_bed     = hifitrimmer_bed                   // [meta, bed]
    hifitrimmer_summary = hifitrimmer_summary               // [meta, summary]
    pbmarkdup_stats     = pbmarkdup_stats                   // [meta, log]
}
