process BGZIPTABIX {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/86/863ca0dbbba30c8367fa4fbd3fa3a84393532fb7b300a5c5c2e70f0dfc475bbf/data'
        : 'community.wave.seqera.io/library/htslib_xz:32f2772a564b3cd2'}"

    input:
    tuple val(meta), path(input), val(max_seq_length)
    tuple val(column_numbers), val(header_lines), val(extension)

    output:
    tuple val(meta), path("*.gz"), path("*.gzi"), emit: gz_index
    tuple val(meta), path("*.tbi"), emit: tbi, optional: true
    tuple val(meta), path("*.csi"), emit: csi, optional: true
    tuple val("${task.process}"), val('bgzip'), eval("bgzip --version | sed '1!d;s/.* //'"), topic: versions, emit: versions_bgzip
    tuple val("${task.process}"), val('tabix'), eval("tabix -h 2>&1 | grep -oP 'Version:\\s*\\K[^\\s]+'"), topic: versions, emit: versions_tabix

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def filter_cut = column_numbers ? "cut -f${column_numbers} |" : ""
    def filter_tail = header_lines ? "tail -n+${header_lines+1} |" : ""
    extension ?= input.name.replaceFirst(/\.(gz|bz2|xz)$/, '').tokenize('.').last()
    def outfile = "${prefix}.${extension}.gz"
    """
    [ "\$(basename ${input})" == "\$(basename ${outfile})" ] && echo "Input and output names cannot be the same" && exit 1

    # The function must read from stdin and create the output file
    # Filters must be Nextflow strings that end with a pipe, so that they can be chained
    filter_compress () {
        ${filter_cut} ${filter_tail} bgzip --threads ${task.cpus} --index ${args} --output ${outfile}
    }

    FILE_TYPE=\$(htsfile ${input})

    # DECOMPRESS is the bash command to decompress and print a file to stdout
    DECOMPRESS=()
    # NEED_COMPRESS is set to 0 when data are already compressed and there's
    # nothing else to do
    NEED_COMPRESS=1

    case "\$FILE_TYPE" in
        *BGZF-compressed*)
            if [[ -z "${filter_cut}${filter_tail}" ]]
            then
                ln -s ${input} ${outfile}
                # Build the .gzi index
                bgzip --threads ${task.cpus} --reindex ${args} ${outfile}
                NEED_COMPRESS=0
            else
                # Note: gzip isn't available in this container
                DECOMPRESS=(bgzip -d -c -@ ${task.cpus})
            fi
            ;;
        *gzip-compressed*)
            # Note: gzip isn't available in this container
            DECOMPRESS=(bgzip -d -c -@ ${task.cpus})
            ;;
        *bzip2-compressed*)
            DECOMPRESS=(bzcat)
            ;;
        *XZ-compressed*)
            DECOMPRESS=(xzcat)
            ;;
        *)
            ;;
    esac

    if ((NEED_COMPRESS))
    then
        # filter_compress is called directly, with input data on its stdin
        # to avoid spawning a sub-shell like "... | filter_compress" would
        if ((\${#DECOMPRESS[@]}))
        then
            filter_compress < <("\${DECOMPRESS[@]}" ${input})
        else
            filter_compress < ${input}
        fi
    fi

    # Now that the file is ready in bgzip format, we can call tabix
    [[ ${max_seq_length} -lt \$(( 2 ** 29 )) ]] && tabix --threads ${task.cpus} ${args2} ${outfile}
    [[ ${max_seq_length} -lt \$(( 2 ** 32 )) ]] && tabix --threads ${task.cpus} --csi ${args2} ${outfile}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    extension ?= input.extension
    // Trick to make the linter pass.
    // nf-core only allows "gzip" to pipe into gz files in stubs.
    // We need bgzip here because gzip is not in the container !
    def outfile = "${prefix}.${extension}.gz"
    """
    echo "" | bgzip > ${outfile}
    touch ${outfile}.gzi
    touch ${outfile}.tbi
    touch ${outfile}.csi
    """
}
