process BAM2FASTQ {
    tag "$meta.id"
    label 'process_medium'

    conda (params.enable_conda ? "bioconda::bam2fastx=1.3.1" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bam2fastx:1.3.1--hb7da652_2' :
        'quay.io/biocontainers/bam2fastx:1.3.1--hb7da652_2' }"

    input:
    tuple val(meta), path(bam)
    path(pbi)

    output:
    tuple val(meta), path("*.fastq.gz"), emit: fastq
    path  "versions.yml"               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    bam2fastq \\
        $args \\
        -o ${prefix} \\
        $bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bam2fastx: 1.3.1
    END_VERSIONS
    """
}
