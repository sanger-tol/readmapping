process SAMTOOLS_FILTERTOFASTQ {
    tag "$meta.id"
    label 'process_low'

    conda "bioconda::samtools=1.21"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.21--h50ea8bc_0' :
        'biocontainers/samtools:1.21--h50ea8bc_0' }"

    input:
    tuple val(meta), path(input), path(index)
    path qname

    output:
    tuple val(meta), path("*.fastq.gz") , emit: fastq
    path  "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def args2 = task.ext.args2 ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools view \\
        --threads $task.cpus \\
        --qname-file ${qname} \\
        --unoutput - \\
        $args \\
        -o /dev/null \\
        $input \\
    | \\
    samtools fastq \\
        $args2 \\
        --threads $task.cpus \\
        -0 ${prefix}.fastq.gz \\
        - \\
        > /dev/null

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo | gzip > ${prefix}.fastq.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
