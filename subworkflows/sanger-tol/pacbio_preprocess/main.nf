include { BLAST_BLASTN                         } from '../../../modules/sanger-tol/blast/blastn/main'
include { BLAST_MAKEBLASTDB                    } from '../../../modules/nf-core/blast/makeblastdb/main'
include { HIFITRIMMER_PROCESSBLAST             } from '../../../modules/nf-core/hifitrimmer/processblast/main'
include { HIFITRIMMER_FILTERBAM                } from '../../../modules/nf-core/hifitrimmer/filterbam/main'
include { LIMA                                 } from '../../../modules/nf-core/lima/main'
include { PBMARKDUP                            } from '../../../modules/nf-core/pbmarkdup/main'

workflow PACBIO_PREPROCESS {

    take:
    ch_reads                    // Channel [meta, input]: input reads in FASTA/FASTQ/BAM format
    ch_adapter_yaml             // Channel [meta, yaml]: yaml file for hifitrimmer adapter trimming
    val_adapter_fasta           // Adapter fasta to make database for blastn
    val_uli_primers             // Primer file for lima
    val_pbmarkdup               // Options to run pbmarkdup

    main:
    lima_reports = channel.empty()
    lima_summary = channel.empty()
    pbmarkdup_stats = channel.empty()
    trimmed_fastx = channel.empty()

    //
    // DEMULTIPLEX WITH LIMA
    //
    if ( val_uli_primers ) {
        LIMA( ch_reads, val_uli_primers )

        lima_reports = lima_reports.mix( LIMA.out.report )
        lima_summary = lima_summary.mix( LIMA.out.summary )

        // prepare input for markdup or trimming
        ch_input_for_md = LIMA.out.bam
            .mix(LIMA.out.fastq)
            .mix(LIMA.out.fasta)
            .mix(LIMA.out.fastqgz)
            .mix( LIMA.out.fastagz )
    } else {
        ch_input_for_md = ch_reads
    }

    //
    // MARKDUP WITH PBMARKDUP
    //
    if ( val_pbmarkdup ) {
        PBMARKDUP( ch_input_for_md )
        pbmarkdup_stats = pbmarkdup_stats.mix( PBMARKDUP.out.log )

        ch_input_pre_trim = PBMARKDUP.out.markduped
    } else {
        // If not running markdup, pass the input to trimming step
        ch_input_pre_trim = ch_input_for_md
    }

    //
    // TRIMMING WITH HIFITRIMMER
    //
    hifitrimmer_summary = channel.empty()
    hifitrimmer_bed = channel.empty()
    if ( val_adapter_fasta ) {
        // Assign ch_input_skip_trimm to those without adapter yaml for trimming
        ch_input_skip_trim = ch_input_pre_trim
            .join(ch_adapter_yaml, by: 0, remainder: true)
            .filter { _meta, _reads, yaml -> !yaml }
            .map { meta, reads, _yaml -> [meta, reads] }

        // Warning for skip trimming
        ch_input_skip_trim
            .subscribe { _meta, reads ->
                log.warn "No adapter YAML provided, skipping adapter trimming step for: ${reads}"
            }

        // PREPARE INPUT FOR TRIMMING
        // Combine adapter yaml to input reads, only those with adapter yaml will be used for trimming, skip those without
        ch_input_to_trim = ch_input_pre_trim
            .combine(ch_adapter_yaml, by: 0)
            .map { meta, reads, _yaml -> [meta, reads] }

        // Make adapter database
        BLAST_MAKEBLASTDB( val_adapter_fasta )

        //
        // ADAPTER SEARCH WITH BLASTN
        //
        // Convert reads to FASTA for BLASTN
        BLAST_BLASTN ( ch_input_to_trim, BLAST_MAKEBLASTDB.out.db.collect(), [],[],[] )

        //
        // PROCESS BLAST OUTPUT WITH HIFITRIMMER PROCESSBLAST
        //
        // Prepare input for Hifitimmer processblast
        ch_input_processblast = BLAST_BLASTN.out.txtgz.combine( ch_adapter_yaml, by: 0 )
            .multiMap { meta, blastn, yaml ->
                blastn: [ meta, blastn ]
                yaml: [ meta, yaml ]
            }

        HIFITRIMMER_PROCESSBLAST ( ch_input_processblast.blastn, ch_input_processblast.yaml )

        hifitrimmer_summary = hifitrimmer_summary.mix ( HIFITRIMMER_PROCESSBLAST.out.summary )
        hifitrimmer_bed = hifitrimmer_bed.mix ( HIFITRIMMER_PROCESSBLAST.out.bed )

        //
        // FILTER READS WITH HIFITRIMMER FILTERBAM
        //
        // Convert FASTA and FASTQ to BAM for hifitrimmer filtering
        ch_input_filterbam = ch_input_to_trim.combine( HIFITRIMMER_PROCESSBLAST.out.bed, by: 0 )
        HIFITRIMMER_FILTERBAM ( ch_input_filterbam )

        trimmed_fastx =  trimmed_fastx.mix( HIFITRIMMER_FILTERBAM.out.filtered )
    } else {
        ch_input_skip_trim = ch_input_pre_trim
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
    trimmed_fastx       = trimmed_fastx                     // [meta, fastx] preprocessed reads in FASTA/FASTQ format
    lima_report         = lima_reports                      // [meta, report]
    lima_summary        = lima_summary                      // [meta, summary]
    hifitrimmer_bed     = hifitrimmer_bed                   // [meta, bed]
    hifitrimmer_summary = hifitrimmer_summary               // [meta, summary]
    pbmarkdup_stat      = pbmarkdup_stats                   // [meta, log]
}
