include { CRAM_FILTER } from '../../modules/local/cram_filter'

workflow CREATE_CRAM_FILTER_INPUT {
    take:
    csv_ch
    fasta

    main:
    ch_versions = Channel.empty()

    // Generate input channel for CRAM_FILTER
    csv_ch
    |splitCsv()
    |combine(fasta)
    |map { cram_id, cram_info, ref_id, ref_dir ->
        tuple([
                id: cram_id.id,
                chunk_id: cram_id.id + "_" + cram_info[5],
                genome_size: ref_id.genome_size,
                read_count: cram_id.read_count
            ],
            file(cram_info[0]),
            cram_info[1],
            cram_info[2],
            cram_info[3],
            cram_info[4],
            cram_info[5],
            cram_info[6],
            ref_dir
        )
    }
    | set { ch_cram_filter_input }

    CRAM_FILTER(ch_cram_filter_input)
    ch_versions = ch_versions.mix(CRAM_FILTER.out.versions)

    emit:
    chunked_cram = CRAM_FILTER.out.cram
    versions = ch_versions
}