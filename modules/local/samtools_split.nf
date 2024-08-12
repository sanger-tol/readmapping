process SAMTOOLS_SPLIT {
    tag "$meta.id"
    label "process_high"

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.20--h50ea8bc_0' :
        'biocontainers/samtools:1.20--h50ea8bc_0' }"

    input:
    tuple val(meta), path(reads)
    tuple val(meta2), path(fasta)

    output:
    tuple val(meta), path("*.bam"), optional: true, emit: chunked_bam
    tuple val(meta), path("*.cram"), optional: true, emit: chunked_cram
    
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def chunk_size = task.ext.chunk_size ?: 10000
    def reference = fasta ? "--reference ${fasta}" : ""
    def file_extension = reads.name.split('\\.')[-1]
    def cpus = task.ext.cpus ?: 1

    """
    # Convert BAM or CRAM to SAM
    if [ "${file_extension}" == "bam" ]; then
        samtools view -@ ${cpus} ${args} ${reads} > ${prefix}.sam

        # Split SAM file into chunks
        split -l ${chunk_size} ${prefix}.sam ${prefix}_part_

        # Convert each chunk back to BAM
        for chunk in ${prefix}_part_*; do
            samtools view -@ ${cpus} -b -h \$chunk > \${chunk}.bam
        done
    elif [ "${file_extension}" == "cram" ]; then
        samtools view -@ ${cpus} ${args} ${reference} ${reads} > ${prefix}.sam
        # Split SAM file into chunks
        split -l ${chunk_size} ${prefix}.sam ${prefix}_part_

        # Convert each chunk back to BAM
        for chunk in ${prefix}_part_*; do
            samtools view -@ ${cpus} -b -h \$chunk > \${chunk}.cram
        done
    else
        echo "Unsupported file type: ${file_extension}"
        exit 1
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' )
    END_VERSIONS
    """
}
