process REMOVE_MASKING {
    // tag "$meta.id"
    // label 'process_medium'

    conda (params.enable_conda ? "conda-forge::gawk=5.1.0" : null)
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gawk:5.1.0' :
        'quay.io/biocontainers/gawk:5.1.0' }"

    input:
    path(genome)

    output:
    path("*.unmasked.fasta"),      emit: fasta
    path  "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    remove_masking.sh $genome

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        GNU Awk: \$(echo \$(awk --version 2>&1) | grep -i awk | sed 's/GNU Awk //; s/,.*//')
    END_VERSIONS
    """
}
