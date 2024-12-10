process SAMTOOLS_COLLATETOFASTQ {
    tag "$meta.id"
    label 'process_medium'

    conda "bioconda::samtools=1.20"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.20--h50ea8bc_0' :
        'biocontainers/samtools:1.20--h50ea8bc_0' }"

    input:
    tuple val(meta), path(input)
    val(interleave)

    output:
    tuple val(meta), path("*_{1,2}.fasta")      , optional:true, emit: fasta
    tuple val(meta), path("*_interleaved.fasta"), optional:true, emit: interleaved
    tuple val(meta), path("*_singleton.fasta")  , optional:true, emit: singleton
    tuple val(meta), path("*_other.fasta")      , optional:true, emit: other
    path  "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output = ( interleave && ! meta.single_end ) ? "> ${prefix}_interleaved.fasta" :
        meta.single_end ? "-1 ${prefix}_1.fasta -s ${prefix}_singleton.fasta" :
        "-1 ${prefix}_1.fasta -2 ${prefix}_2.fasta -s ${prefix}_singleton.fasta"
    """
    samtools fasta \\
        $args \\
        --threads ${task.cpus-1} \\
        -0 ${prefix}_other.fasta \\
        $input \\
        $output

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
