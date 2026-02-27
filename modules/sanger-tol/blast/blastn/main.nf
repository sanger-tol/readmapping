// Adapted from https://github.com/nf-core/modules/tree/master/modules/nf-core/blast/blastn

process BLAST_BLASTN {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/6d/6daff9692203a560ac963c14eb1dd77190be4191e08702b2311e9a6175892748/data':
        'community.wave.seqera.io/library/blast_htslib_samtools_seqkit:45ece1dc474127e2' }"

    input:
    tuple val(meta) , path(input)
    tuple val(meta2), path(db)
    path taxidlist
    val taxids
    val negative_tax

    output:
    tuple val(meta), path('*.txt.gz'), emit: txtgz
    tuple val("${task.process}"), val('blastn'), eval('blastn -version 2>&1 | sed "s/^.*blastn: //; s/ .*$//"'), emit: versions_blast, topic: versions
    tuple val("${task.process}"), val('samtools'), eval('samtools --version | head -1 | sed -e "s/samtools //"'), emit: versions_samtools, topic: versions
    tuple val("${task.process}"), val('seqkit'), eval('seqkit | sed "3!d; s/Version: //"'), emit: versions_seqkit, topic: versions


    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def is_compressed = (input ==~ /.*\.(fasta|fa)\.gz$/) ? true : false
    def fasta_name = is_compressed ? input.getBaseName() : input
    def negative_tax_cmd = negative_tax ? "negative_" : ""
    def taxidlist_cmd = taxidlist ? "-${negative_tax_cmd}taxidlist ${taxidlist}" : ""
    def taxids_cmd = taxids ? "-${negative_tax_cmd}taxids ${taxids}" : ""
    if (taxidlist_cmd.any() && taxids_cmd.any()) {
        log.error("ERROR: taxidlist and taxids can not be used at the same time, choose only one argument to use for tax id filtering.")
    }

    // Convert input to fasta if needed
    def args1 = task.ext.args1 ?: ""
    def args2 = task.ext.args2 ?: ""
    def input_content = input.name.endsWith('bam') ? "<(samtools fasta ${args1} --threads ${task.cpus} ${input})" :
                    (input.name ==~ /.*\.(fastq|fq)(\.gz)?$/) ? "<(seqkit fq2fa ${args2} -j ${task.cpus} ${input})" :
                    fasta_name


    """
    if [ "${is_compressed}" == "true" ]; then
        gzip -c -d ${input} > ${fasta_name}
    fi

    export BLASTDB=${db}

    DB=`find -L ./ -name "*.nal" | sed 's/\\.nal\$//'`
    if [ -z "\$DB" ]; then
        DB=`find -L ./ -name "*.nin" | sed 's/\\.nin\$//'`
    fi
    echo Using \$DB

    blastn \\
        -num_threads ${task.cpus} \\
        -db \$DB \\
        -query ${input_content} \\
        ${taxidlist_cmd} \\
        ${taxids_cmd} \\
        ${args} \\
        | gzip -c > ${prefix}.txt.gz
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    gzip -c /dev/null > ${prefix}.txt.gz
    """
}
