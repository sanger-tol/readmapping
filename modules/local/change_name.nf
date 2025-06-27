process CHANGE_NAME {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:20.04' :
        'docker.io/ubuntu:20.04' }"

    input:
    tuple val(meta), path(file)

    output:
    tuple val(meta), path("*.${file.extension}"), emit: file
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def VERSION = "9.1" // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    def prefix = task.ext.prefix ?: "${meta.id}"
    def new_fn = "${prefix}.${file.extension}"
    """
    ln -s ${file} ${new_fn}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: $VERSION
    END_VERSIONS
    """

    stub:
    def VERSION = "9.1" // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    """
    touch ${new_fn}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: $VERSION
    END_VERSIONS
    """
}

