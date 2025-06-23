process CRAM_FILTER {
    tag "$meta.chunk_id"
    label "process_high"

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-1a6fe65bd6674daba65066aa796ed8f5e8b4687b:688e175eb0db54de17822ba7810cc9e20fa06dd5-0' :
        'biocontainers/mulled-v2-1a6fe65bd6674daba65066aa796ed8f5e8b4687b:688e175eb0db54de17822ba7810cc9e20fa06dd5-0' }"

    input:
    tuple val(meta), path(cramfile), path(cramindex), val(from), val(to), val(base), val(chunkid), val(rglines), path(reference)

    output:
    tuple val(meta), path("*.cram"), emit: cram
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def VERSION = "1.15" // Staden_io versions break the pipeline
    """
    cram_filter -n ${from}-${to} ${cramfile} ${prefix}_${base}_${chunkid}.cram

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' )
        staden_io: $VERSION
    END_VERSIONS
    """

    stub:
    def prefix  = task.ext.prefix ?: "${meta.id}"
    def base    = "45022_3#2"
    def chunkid = "1"
    """
    touch ${prefix}_${base}_${chunkid}_filtered.cram

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' )
        staden_io: $VERSION
    END_VERSIONS
    """
}
