// Copied from https://github.com/nf-core/modules/pull/3310
// Author: Matthias De Smet, https://github.com/matthdsm
process SAMTOOLS_SORMADUP {
    tag "$meta.id"
    label 'process_medium'

    conda "bioconda::samtools=1.21"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.21--h50ea8bc_0' :
        'biocontainers/samtools:1.21--h50ea8bc_0' }"

    input:
    tuple val(meta), path(input)
    tuple val(meta2), path(fasta)

    output:
    tuple val(meta), path("*.{bam,cram}")   , emit: bam
    tuple val(meta), path("*.{bai,crai}")   , optional:true, emit: bam_index
    tuple val(meta), path("*.metrics")      , emit: metrics
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args  = task.ext.args  ?: ''
    def args2 = task.ext.args2 ?: ''
    def args3 = task.ext.args3 ?: ''
    def args4 = task.ext.args4 ?: ''

    def prefix = task.ext.prefix ?: "${meta.id}"
    def extension = args.contains("--output-fmt sam") ? "sam" :
                    args.contains("--output-fmt bam") ? "bam" :
                    args.contains("--output-fmt cram") ? "cram" :
                    "bam"
    def reference = fasta ? "--reference ${fasta}" : ""

    """
    samtools collate \\
        $args \\
        -O \\
        -u \\
        -T ${prefix}.collate \\
        --threads $task.cpus \\
        ${reference} \\
        ${input}  \\
        - \\
    | \\
    samtools fixmate \\
        $args2 \\
        -m \\
        -u \\
        --threads $task.cpus \\
        - \\
        - \\
    | \\
    samtools sort \\
        $args3 \\
        -u \\
        -T ${prefix}.sort \\
        --threads $task.cpus \\
        - \\
    | \\
    samtools markdup \\
        -T ${prefix}.markdup \\
        -f ${prefix}.metrics \\
        --threads $task.cpus \\
        $args4 \\
        - \\
        ${prefix}.${extension}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
