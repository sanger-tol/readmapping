//
// Prepare read-group metadata from optional extra_header and BAM input headers
//

include { SAMTOOLS_SPLITHEADER } from '../../modules/nf-core/samtools/splitheader/main'

workflow PREPARE_READ_GROUPS {
    take:
    reads        // channel: [ val(meta), /path/to/read_file ]
    rg_mode      // string: read-group mode: 'long' (minimap2 style) or 'short' (samtools addreplacerg style)

    main:
    // Build mode-specific RG prefix once and reuse it for all reads in this invocation.
    def rg_lead = rg_mode == 'long' ? '-y' : ''
    def rg_flag = rg_mode == 'long' ? '-R' : '-r'

    // Pre-populate read_group for all inputs; downstream steps may override it from extracted @RG lines
    ch_reads_prefixed = reads.map { meta, read_file -> [meta + [read_group: "${rg_lead} ${rg_flag} $meta.read_group", replace_rg: true], read_file] }

    ch_reads_extra_header = ch_reads_prefixed
        .branch { meta, read_file ->
            // Inputs with explicit extra_header metadata should be parsed directly
            has_extra_header: meta.extra_header != []
                return [meta + [read_file: read_file], meta.extra_header]
            // For BAM/CRAM without extra_header metadata, extract header from the alignment file.
            no_extra_header_bam_cram: meta.extra_header == [] && read_file.name ==~ /.*\.(bam|cram)$/
            // FASTQ and remaining inputs keep the pre-populated read_group.
            no_extra_header_fastq: true
        }

    // Extract @RG/@PG from provided extra_header files and BAM/CRAM headers
    SAMTOOLS_SPLITHEADER(ch_reads_extra_header.has_extra_header.mix(ch_reads_extra_header.no_extra_header_bam_cram))

    ch_reads_with_rg = SAMTOOLS_SPLITHEADER.out.readgroup
        .join(SAMTOOLS_SPLITHEADER.out.programs)
        .join(ch_reads_extra_header.has_extra_header.mix(ch_reads_extra_header.no_extra_header_bam_cram), by: 0)
        .map { meta, rg_file, program_file, read_files ->
            def rglines = file(rg_file).readLines()
            // Prefer extracted @RG lines; fallback to the existing read_group only when extraction is empty
            def rg_args = rglines ? [
                rg_lead,
                rglines.collect { line ->
                    // Add SM when not present to avoid errors from downstream tools (e.g. variant callers)
                    def l = line.contains('SM:') ? line
                            : meta.sample ? "${line}\tSM:${meta.sample}"
                            : "${line}\tSM:${meta.id}"
                    "${rg_flag} '${l.replaceAll("\t", "\\\\t")}'"
                }.join(' ')
            ].findAll { it }.join(' ')
            : (meta.read_group ?: '')

            def output_read_files = meta.read_file ?: read_files
            // If RG came from an existing BAM/CRAM header, and no extra RG provided to overwrite, preserve it and avoid replacing downstream
            // If PG came from an existing BAM/CRAM header, and no extra PG provided to overwrite, preserve it and avoid replacing downstream
            def replace_rg = !meta.extra_header && rglines ? false : true
            def add_pg = !meta.extra_header && program_file ? false : true
            def new_meta = meta.subMap(meta.keySet() - ['read_file']) + [read_group: rg_args, replace_rg: replace_rg, add_pg: add_pg]
            [new_meta, output_read_files]
        }
        .mix(ch_reads_extra_header.no_extra_header_fastq)

    emit:
    reads = ch_reads_with_rg       // channel: [ val(meta), /path/to/read_file ]
}
