process SAMTOOLS_REHEADER {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.22.1--h96c455f_0' :
        'biocontainers/samtools:1.22.1--h96c455f_0' }"

    input:
    tuple val(meta), path(file, stageAs: "input/*")
    path(header)

    output:
    tuple val(meta), path("${prefix}.bam") , optional:true, emit: bam
    tuple val(meta), path("${prefix}.cram"), optional:true, emit: cram
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), topic: versions, emit: versions_samtools

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    suffix = file.getExtension()

    if ("$file" == "${prefix}.${suffix}") error "Input and output names are the same, use \"task.ext.prefix\" to disambiguate!"
    """
    # Replace SQ lines with those from external template
    ( samtools view --no-PG --header-only ${file} | \\
    grep -v ^@SQ && grep ^@SQ ${header} ) > temp.header.sam

    # custom sort for readability (retain order of insertion but sort groups by tag)
    ( grep ^@HD temp.header.sam || true && \\
    grep ^@SQ temp.header.sam || true && \\
    grep ^@RG temp.header.sam || true && \\
    grep ^@PG temp.header.sam || true && \\
    grep -v -E '^@HD|^@SQ|^@RG|^@PG' temp.header.sam || true; \\
    ) > temp.sorted.header.sam

    # Insert new header into file
    samtools reheader temp.sorted.header.sam ${file} > ${prefix}.${suffix}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    suffix = file.getExtension()
    """
    touch ${prefix}.${suffix}
    """
}
