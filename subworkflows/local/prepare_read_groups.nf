//
// Prepare read-group metadata from optional extra_header and BAM input headers
//

include { SAMTOOLS_SPLITHEADER as SAMTOOLS_SPLITHEADER_EXTRA } from '../../modules/nf-core/samtools/splitheader/main'
include { SAMTOOLS_SPLITHEADER as SAMTOOLS_SPLITHEADER_BAM   } from '../../modules/nf-core/samtools/splitheader/main'

workflow PREPARE_READ_GROUPS {
    take:
    reads        // channel: [ val(meta), /path/to/read_file ]
    rg_mode      // string: read-group mode: 'long' (minimap2 style) or 'short' (samtools addreplacerg style)

    main:
    // Build mode-specific RG prefix once and reuse it for all reads in this invocation.
    def rg_lead = rg_mode == 'long' ? '-y' : ''
    def rg_flag = rg_mode == 'long' ? '-R' : '-r'

    // Pre-populate read_group for all inputs; downstream steps may override it from extracted @RG lines
    ch_reads_prefixed = reads.map { meta, read_file ->
        [meta + [read_group: "${rg_lead} ${rg_flag} $meta.read_group", replace_rg: true, read_file: read_file], read_file]
    }

    ch_branched = ch_reads_prefixed.branch { meta, read_file ->
        // An input may match both extra and bam_cram extraction: extra_header is parsed here; BAM/CRAM is also parsed below as an independent fallback source
        has_extra: meta.extra_header != []
            return [meta, meta.extra_header]
        fastq:     !(read_file.name ==~ /.*\.(bam|cram)$/)
        other:     true
    }
    ch_bam_cram = ch_reads_prefixed.filter { _meta, read_file -> read_file.name ==~ /.*\.(bam|cram)$/ }

    // Extract @RG/@PG from extra_header files and (independently) from BAM/CRAM alignment files
    SAMTOOLS_SPLITHEADER_EXTRA(ch_branched.has_extra)
    SAMTOOLS_SPLITHEADER_BAM(ch_bam_cram)

    // Tag each result with its source so the resolver can pick precedence: extra_header > bam > precomputed
    ch_extra = SAMTOOLS_SPLITHEADER_EXTRA.out.readgroup.join(SAMTOOLS_SPLITHEADER_EXTRA.out.programs).map { it + ['extra'] }
    ch_bam   = SAMTOOLS_SPLITHEADER_BAM.out.readgroup.join(SAMTOOLS_SPLITHEADER_BAM.out.programs).map { it + ['bam'] }

    // Group all extracted headers per meta; inputs may yield 0, 1 (extra or bam only), or 2 (both) entries
    ch_resolved = ch_extra.mix(ch_bam)
        .map { meta, rg, pg, src -> [meta.id, meta, rg, pg, src] }
        .groupTuple()
        .map { _id, metas, rgs, pgs, srcs ->
            def meta = metas[0]
            def bySrc = [srcs, rgs, pgs].transpose().collectEntries { src, rg, pg -> [(src): [rg: rg, pg: pg]] }
            // RG: prefer extra_header lines; fall back to BAM @RG; finally fall back to precomputed meta.read_group
            def picked_rg = ['extra', 'bam'].findResult { src ->
                def entry = bySrc[src]
                if (!entry) return null
                def lines = file(entry.rg).readLines()
                lines ? [src: src, rglines: lines] : null
            }
            // PG: inject @PG downstream only when extra_header supplies them; otherwise preserve whatever the BAM/CRAM already has
            def extra_has_pg = bySrc.extra && !file(bySrc.extra.pg).readLines().isEmpty()

            def from_bam = picked_rg?.src == 'bam'
            def rg_args = picked_rg ? [rg_lead, picked_rg.rglines.collect { line ->
                // Add SM when not present to avoid errors from downstream tools (e.g. variant callers)
                def l = line.contains('SM:') ? line : "${line}\tSM:${meta.sample ?: meta.id}"
                "${rg_flag} '${l.replaceAll('\t', '\\\\t')}'"
            }.join(' ')].findAll().join(' ')
            : (meta.read_group ?: '')

            // Don't replace RG when it already comes from the BAM/CRAM header itself
            def replace_rg = !(from_bam && picked_rg)
            def new_meta = meta.subMap(meta.keySet() - ['read_file']) + [read_group: rg_args, replace_rg: replace_rg, add_pg: extra_has_pg]
            [new_meta, meta.read_file]
        }

    ch_reads_with_rg = ch_resolved.mix(ch_branched.fastq.map { meta, rf -> [meta.subMap(meta.keySet() - ['read_file']), rf] })

    emit:
    reads = ch_reads_with_rg               // channel: [ val(meta), /path/to/read_file ]
}
