process SAMTOOLS_REHEADER {
    tag "$meta.id"
    label 'process_single'

    conda "bioconda::samtools=1.17"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.17--h00cdaf9_0' :
        'biocontainers/samtools:1.17--h00cdaf9_0' }"

    input:
    tuple val(meta), path(file), path(header)

    output:
    tuple val(meta), path("*.${meta.suffix}"), emit: bam
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = "${meta.suffix}"

    if ("$file" == "${prefix}.${suffix}") error "Input and output names are the same, use \"task.ext.prefix\" to disambiguate!"
    """
    # Replace SQ lines with those from external template
    ( samtools view --no-PG --header-only ${file} | \\
    grep -v ^@SQ && grep ^@SQ ${header} ) > .temp.header.sam

    # custom sort for readability (retain order of insertion but sort groups by tag)
    ( grep ^@HD .temp.header.sam && \
    grep ^@SQ .temp.header.sam && \
    grep ^@RG .temp.header.sam && \
    grep ^@PG .temp.header.sam && \
    if grep -q -E -v '^@HD|^@SQ|^@RG|^@PG' .temp.header.sam; then \
        grep -v -E '^@HD|^@SQ|^@RG|^@PG' .temp.header.sam; \
    fi; ) > .temp.sorted.header.sam

    # Insert new header into file
    samtools reheader .temp.sorted.header.sam ${file} > ${prefix}.${suffix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = file.name.split('\\.')[-1]
    """
    touch ${prefix}.${suffix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
