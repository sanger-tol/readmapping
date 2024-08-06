process MINIMAP2_SPLICE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/minimap2:2.24--h5bf99c6_0':
        'biocontainers/minimap2:2.24--h5bf99c6_0' }"

    input:
    tuple val(meta) , path(fasta)
    path(db)
   
    output:
    tuple val(meta), path('*.paf'), emit: paf
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def is_compressed = fasta.getExtension() == "gz" ? true : false
    def fasta_name = is_compressed ? fasta.getBaseName() : fasta

    """
    if [ "${is_compressed}" == "true" ]; then
        gzip -c -d ${fasta} > ${fasta_name}
    fi

    minimap2 $args -t $task.cpus ${db} ${fasta_name} > ${prefix}.paf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version | grep minimap2 | sed 's/minimap2 //')
    END_VERSIONS
    """
}