process SAMTOOLS_VIEW {
    tag "$meta.id"
    label 'process_samtools'

    conda (params.enable_conda ? "bioconda::samtools=1.15" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.15--h1170115_1' :
        'quay.io/biocontainers/samtools:1.15--h1170115_1' }"

    input:
    tuple val(meta), path(input)
    path fasta

    output:
    tuple val(meta), path("*.cram"), emit: cram
    path  "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: (meta.library == null) ? "${fasta.baseName}.${meta.datatype}.${meta.id}" : "${fasta.baseName}.${meta.datatype}.${meta.library}"
    """
    samtools \\
        view \\
        --threads ${task.cpus-1} \\
        --reference $fasta -C \\
        $args \\
        $input \\
        > ${prefix}.cram

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
