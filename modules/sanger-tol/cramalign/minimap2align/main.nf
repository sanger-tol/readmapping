process CRAMALIGN_MINIMAP2ALIGN {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/65/65858e733832166824cfd05291fc456bdf219b02baa3944c2c92efad86a6ee7f/data' :
        'community.wave.seqera.io/library/htslib_minimap2_samtools_gawk_perl:6729620c63652154' }"

    input:
    tuple val(meta),  path(cram),  path(crai), val(rglines)
    tuple val(meta2), path(index), path(reference)
    tuple val(chunkn), val(range)

    output:
    tuple val(meta), path("*.bam"), emit: bam
    tuple val("${task.process}"), val('minimap2'), eval('minimap2 --version | sed "s/minimap2 //g"'), emit: versions_minimap2, topic: versions
    tuple val("${task.process}"), val('samtools'), eval('samtools --version | head -1 | sed -e "s/samtools //"'), emit: versions_samtools, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // WARNING: This module includes insert_cram_pg_header as a module binary in
    // ${moduleDir}/resources/usr/bin/insert_cram_pg_header. To use this module, you will
    // either have to copy this file to ${projectDir}/bin or set the option
    // nextflow.enable.moduleBinaries = true
    // in your nextflow.config file.
    def args  = task.ext.args  ?: ''
    def args2 = task.ext.args2 ?: '-t' // copy RG, BC and QT tags to the FASTQ header line
    def args3 = task.ext.args3 ?: ''
    def args5 = task.ext.args5 ?: ''
    def prefix = task.ext.prefix ?: "${cram}.${chunkn}.${meta.id}"
    def post_filter = task.ext.args4 ? "samtools view -h ${task.ext.args4} |" : ''
    def rg_arg = rglines ? '-y ' + rglines.collect { line ->
            // Add SM when not present to avoid errors from downstream tool (e.g. variant callers)
            def l = line.contains("SM:") ? line : "${line}\tSM:${meta.id}"
            "-R '${l.replaceAll("\t", "\\\\t")}'"
        }.join(' ')
        : ''
    """
    samtools view -H ${cram} | grep ^@PG > ${prefix}_cram_pg.tmp

    samtools cat ${args} -r "#:${range[0]}-${range[1]}" ${cram} | \\
        samtools fastq ${args2} - |  \\
        minimap2 -t${task.cpus} ${args3} ${index} ${rg_arg} - | \\
        insert_cram_pg_header.awk -v pgfile="${prefix}_cram_pg.tmp" | \
        ${post_filter} \\
        samtools sort ${args5} -@${task.cpus} -T ${prefix}_sort_tmp -o ${prefix}.bam -

    rm ${prefix}_cram_pg.tmp
    """

    stub:
    def prefix  = task.ext.prefix ?: "${cram}.${chunkn}.${meta.id}"
    """
    touch ${prefix}.bam
    """
}
