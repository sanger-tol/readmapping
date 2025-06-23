process BLOBTK_DEPTH {
    tag "${meta.id}"
    label 'process_single'

    if (workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1) {
        exit 1, "BLOBTOOLKIT_DEPTH module does not support Conda. Please use Docker / Singularity / Podman instead."
    }
    container "docker.io/genomehubs/blobtk:0.6.5"

    input:
    tuple val(meta), path(cram), path(bai)

    output:
    tuple val(meta), path('*.coverage.bedGraph')    , emit: bedgraph
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    blobtk depth \\
        -c ${cram} \\
        $args \\
        -O ${prefix}.coverage.bedGraph \\


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        blobtk: \$(blobtk --version | cut -d' ' -f2)
    END_VERSIONS
    """
}
