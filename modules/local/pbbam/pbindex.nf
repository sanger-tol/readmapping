process PBBAM_PBINDEX {
    tag "$meta.id"
    label 'process_low'

    conda (params.enable_conda ? "bioconda::pbbam=2.1.0" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pbbam:2.1.0--h3f0f298_1' :
        'quay.io/biocontainers/pbbam:2.1.0--h3f0f298_1' }"

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.pbi"), emit: pbi
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    pbindex -j $task.cpus $args $bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pbbam: \$( pbindex --version | grep pbindex | sed 's/pbindex //' | sed 's/ .*//' )
    END_VERSIONS
    """
}
