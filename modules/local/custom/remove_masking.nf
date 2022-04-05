process REMOVE_MASKING {
    tag "$meta.id"
    // label 'process_medium'

    if (params.enable_conda) {
        exit 1, "Conda environments cannot be used. Please use docker or singularity containers."
    }
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:20.04' :
        'ubuntu:20.04' }"

    input:
    tuple val(meta), path(genome)
    path fasta

    output:
    tuple val(meta), path("*.fasta"), emit: fasta
    path  "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    awk 'BEGIN{FS=" "}{if(!/>/){print toupper($0)}else{print $0}}' $genome > ${genome.baseName}.unmasked.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ubuntu: 20.04
    END_VERSIONS
    """
}
