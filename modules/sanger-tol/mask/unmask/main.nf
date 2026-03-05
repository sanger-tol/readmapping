process MASK_UNMASK {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/gawk:5.3.1'
        : 'biocontainers/gawk:5.3.1'}"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.unmasked.fa"), emit: unmasked
    tuple val("${task.process}"), val('unmask'), eval('echo 1.0'), emit: versions_unmask, topic: versions
    tuple val("${task.process}"), val('gawk'), eval('gawk --version | grep -o -E "[0-9]+(.[0-9]+)+" | head -n1'), emit: versions_gawk, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def input = fasta.extension == "gz" ? "<(zcat ${fasta})" : "${fasta}"
    """
    awk 'BEGIN { FS = " " } \\
        { if ( !/^>/ ) { print toupper(\$0) } \\
          else { print \$0 } }' \\
        ${args} \\
        ${input} \\
        > ${prefix}.unmasked.fa
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.unmasked.fa
    """
}
