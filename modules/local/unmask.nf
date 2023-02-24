process UNMASK {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::gawk=5.1.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gawk:5.1.0' :
        'quay.io/biocontainers/gawk:5.1.0' }"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.fasta"), emit: fasta
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    awk 'BEGIN { FS = " " } \\
        { if ( !/>/ ) { print toupper(\$0) } \\
        else { print \$0 } \\
        }' $fasta \\
        > ${prefix}.unmasked.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        awk: \$( awk --version | grep -oP '(?<=GNU Awk ).*?(?=, )' )
    END_VERSIONS
    """
}
