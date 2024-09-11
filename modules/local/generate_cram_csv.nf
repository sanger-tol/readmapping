process GENERATE_CRAM_CSV {
    tag "${meta.id}"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'quay.io/sanger-tol/cramfilter_bwamem2_minimap2_samtools_perl:0.001-c1' :
        'sanger-tol/cramfilter_bwamem2_minimap2_samtools_perl:0.001-c1' }"

    input:
    tuple val(meta), path(crampath), path(crai)


    output:
    tuple val(meta), path('*.csv'), emit: csv
    path "versions.yml",            emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    generate_cram_csv.sh $crampath ${prefix}_cram.csv $crai ${params.chunk_size}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' )
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//' )
    END_VERSIONS
    """
}
