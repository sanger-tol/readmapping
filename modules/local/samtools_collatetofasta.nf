process SAMTOOLS_COLLATETOFASTA {
    tag "$meta.id"
    label 'process_medium'

    conda "bioconda::samtools=1.17"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.17--h00cdaf9_0' :
        'biocontainers/samtools:1.17--h00cdaf9_0' }"

    input:
    tuple val(meta), path(input)

    output:
    tuple val(meta), path("*.fasta"), emit: fasta
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args  = task.ext.args  ?: ''
    def args2 = task.ext.args2 ?: ''

    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools collate \\
        $args \\
        -O \\
        -u \\
        -T ${prefix}.collate \\
        --threads $task.cpus \\
        ${input} \\
    | \\
    samtools fasta \\
        $args2 \\
        --threads $task.cpus \\
        -0 ${prefix}.fasta \\
        > /dev/null

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
