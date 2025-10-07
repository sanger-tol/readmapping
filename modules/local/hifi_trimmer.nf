process HIFI_TRIMMER {
    tag "$meta.id"

    container "biocontainers/hifi_trimmer:1.2.2--pyhdfd78af_0"

    input:
    tuple val(meta), path(bam), path(blast_out)
    path(yaml)


    output:
    tuple val(meta), path("*.hifi_trimmer.fastq.gz")          , emit: fastq
    tuple val(meta), path("*.bed.gz")                         , emit: bed
    tuple val(meta), path("*.summary.json")                   , emit: json
    path  "versions.yml"                                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args = task.ext.args ? task.ext.args : ''
    def barcode_sub = meta.barcode ? "sed -i \"s|SAMPLEBARCODE|${meta.barcode}|g\" ${yaml}" : ''
    """
    $barcode_sub
    hifi_trimmer process_blast $blast_out $yaml
    hifi_trimmer filter_bam $args $bam *.bed.gz ${prefix}.hifi_trimmer.fastq.gz -t $task.cpus

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
       \$(hifi_trimmer --version | sed 's/, version/: /')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.hifi_trimmer.fastq.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
       \$(hifi_trimmer --version | sed 's/, version/: /')
    END_VERSIONS
    """
}
