process BLOBTK_DEPTH {
    tag "${meta.id}"
    label 'process_single'

    container "docker.io/genomehubs/blobtk:0.6.5"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path('*.coverage.bedGraph'), emit: bedgraph
    path "versions.yml"                         , emit: versions

    when:
    (task.ext.when == null || task.ext.when)

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    blobtk depth \\
        -b ${bam} \\
        $args \\
        -O ${prefix}.coverage.bedGraph

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        blobtk: \$(blobtk --version | cut -d' ' -f2)
    END_VERSIONS
    """
}
