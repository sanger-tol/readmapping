process CHANGE_NAME {
    tag "$meta.id"
    executor 'local'

    input:
    tuple val(meta), path(file)

    output:
    tuple val(meta), path("*.${file.extension}"), emit: file

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def new_fn = "${prefix}.${file.extension}"
    """
    ln -s ${file} ${new_fn}
    """

    stub:
    """
    touch ${new_fn}
    """
}

