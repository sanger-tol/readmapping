process TRIMGALORE {
    tag "${meta.id}"
    label 'process_medium'
    label 'process_low_memory'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/11/11bc3d76e7b1b143cee7a17d2c5ef35e75fa1dd1a0c96b6edb3cbb8a979283ce/data' :
        'community.wave.seqera.io/library/samtools_trim-galore:7e061ee12ed867cb'}"

    input:
    tuple val(meta), path(cram)

    output://GO THROUGH OUTPUTS TO MAKE SURE WE ARE KEEPING WHAT WE WANT - pass report to multiqc
    tuple val(meta), path("*{trimmed,val}.cram")                       , emit: cram 
    tuple val(meta), path("*report.txt")                               , emit: log     , optional: true
    tuple val(meta), path("*.html")                                    , emit: html    , optional: true
    tuple val(meta), path("*.zip")                                     , emit: zip     , optional: true
    tuple val("${task.process}"), val("trimgalore"), eval('trim_galore --version | grep -Eo "[0-9]+(\\.[0-9]+)+"'), topic: versions, emit: versions_trimgalore

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: '--preserve-tags  RG,BC,QT --poly_a'
    // Calculate number of --cores for TrimGalore based on value of task.cpus
    // See: https://github.com/FelixKrueger/TrimGalore/blob/master/CHANGELOG.md#version-060-release-on-1-mar-2019
    // See: https://github.com/nf-core/atacseq/pull/65
    def cores = 1
    if (task.cpus) {
        cores = (task.cpus as int) - 4
        if (cores < 1) {
            cores = 1
        }
        if (cores > 8) {
            cores = 8
        }
    }

    //Convert from cram to unaligned bam and pass to trim_galore 
    

    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools view -@ ${task.cpus} -O BAM ${cram} -o temp.bam 
    trim_galore \\
        ${args} \\
        --cores ${cores} \\
        --paired \\
        --output-format ubam \\
        temp.bam
   samtools view -@ ${task.cpus} -C temp_val.bam \\
        -o ${prefix}_val.cram
    rm temp.bam
    rm temp_val.bam
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    output_command = "echo '' | gzip > ${prefix}_val.cram ;"
    output_command += "touch ${prefix}_1.fastq.gz_trimming_report.txt ;"
    output_command += "touch ${prefix}_2.fastq.gz_trimming_report.txt"
    """
    ${output_command}
    """
}
