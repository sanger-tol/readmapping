process STAR_ALIGN {
    tag "$meta.id"
    label "process_high"

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/26/268b4c9c6cbf8fa6606c9b7fd4fafce18bf2c931d1a809a0ce51b105ec06c89d/data' :
        'community.wave.seqera.io/library/htslib_samtools_star_gawk:ae438e9a604351a4' }"
  
    input:
    tuple val(meta),  path(cram),  path(crai), val(rglines)
    tuple val(meta2), path(index), path(assembly)
    tuple val(chunkn), val(range)

    output:
    tuple val(meta), path("*.star.bam"), emit: bam
    tuple val("${task.process}"), val('star'), eval('STAR --version | sed -e "s/STAR_//g"'), emit: versions_star, topic: versions
    tuple val("${task.process}"), val('samtools'), eval('samtools --version | head -1 | sed -e "s/samtools //"'), emit: versions_samtools, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix  = task.ext.prefix ?: "${cram}.${chunkn}.${meta.id}"
    def args1 = task.ext.args1 ?: ''
    def args2 = task.ext.args2 ?: '-t' // copy RG, BC and QT tags to the FASTQ header line
    def args3 = task.ext.args3 ?: "--outSAMtype BAM Unsorted --outSAMattrRGline 'ID:$prefix' 'SM:$prefix'"
    def args4 = task.ext.args4 ?: '-m'
    def args5 = task.ext.args5 ?: ''
    def args6 = task.ext.args6 ?: ''
    // Prepare read group arguments if rglines are found, else, empty string
    def rg_arg = rglines ? '-C ' + rglines.collect { line ->
            // Add SM when not present to avoid errors from downstream tool (e.g. variant callers)
            def l = line.contains("SM:") ? line
                : meta.sample ? "${line}\tSM:${meta.sample}"
                : "${line}\tSM:${meta.id}"
            "-H '${l.replaceAll("\t", "\\\\t")}'"
        }.join(' ')
        : ''
    """

    samtools cat ${args1} -r "#:${range[0]}-${range[1]}" ${cram} |\\
        samtools fastq ${args2} -1 read_1.fastq -2 read_2.fastq -0 /dev/null -s /dev/null
        STAR \\
        --genomeDir $index \\
        --runThreadN $task.cpus \\
        --outFileNamePrefix $prefix. \\
        $args3 \\
        --readFilesIn read_1.fastq read_2.fastq
        samtools fixmate ${args4} ${prefix}.Aligned.out.bam - |\\
        samtools view -h ${args5} |\\
        samtools sort ${args6} -@${task.cpus} -T ${prefix}_tmp -o ${prefix}.star.bam -
    """

    stub:
    def prefix  = task.ext.prefix ?: "${cram}.${chunkn}.${meta.id}"
    """
    touch ${prefix}.star.bam
    """
}
