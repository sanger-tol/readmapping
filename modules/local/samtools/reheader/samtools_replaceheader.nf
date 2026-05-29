process SAMTOOLS_REHEADER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/8c/8c5d2818c8b9f58e1fba77ce219fdaf32087ae53e857c4a496402978af26e78c/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.23.1--5b6bb4ede7e612e5'}"

    input:
    tuple val(meta), path(file, stageAs: "input/*"), path(sample_extra_header, stageAs: "extra_header/*")
    path(header_template)

    output:
    tuple val(meta), path("${prefix}.bam") , optional:true, emit: bam
    tuple val(meta), path("${prefix}.cram"), optional:true, emit: cram
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), topic: versions, emit: versions_samtools

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    suffix = file.getExtension()
    def sq_template = header_template ? " | grep -v ^@SQ && grep '^@SQ' ${header_template}" : ""
    // Suffix all PG IDs from sample extra_header to keep them distinct from native file-header PG IDs.
    // Also rewrite matching PP references so the extra-header PG chain remains intact after suffixing.
    def pg_extra = sample_extra_header ? "awk 'BEGIN { FS = OFS = \"\\t\" } FNR == NR { if (\$1 == \"@PG\") for (i = 1; i <= NF; i++) if (\$i ~ /^ID:/) { ids[substr(\$i, 4)] = 1; break } next } \$1 == \"@PG\" { for (i = 1; i <= NF; i++) { if (\$i ~ /^ID:/) { \$i = \$i \".extra_header\" } else if (\$i ~ /^PP:/) { pp = substr(\$i, 4); if (pp in ids) \$i = \"PP:\" pp \".extra_header\" } } print }' ${sample_extra_header} ${sample_extra_header} || true" : "true"

    if ("$file" == "${prefix}.${suffix}") error "Input and output names are the same, use \"task.ext.prefix\" to disambiguate!"
    """
    # Replace SQ lines with those from external template
    ( samtools view --no-PG --header-only ${file} \\
        ${sq_template} ) > temp.header.sam

    # custom sort for readability (retain order of insertion but sort groups by tag)
    # Add PG lines from sample header
    # Sort order: HD, SQ, RG, extra PG, PG, other
    ( grep ^@HD temp.header.sam || true && \\
    grep ^@SQ temp.header.sam || true && \\
    grep ^@RG temp.header.sam || true && \\
    ${pg_extra} && \\
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
