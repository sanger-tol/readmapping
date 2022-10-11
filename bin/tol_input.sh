#!/bin/bash

if [ $# -ne 2 ]; then echo -e "Script to create a samplesheet for a species.\nUsage: $0 <tol_id> <tol_project_dir>.\nVersion: 1.1"; exit 1; fi

id="$1"
data="$2/data"

if [[ ! -d "$data" ]]; then echo "Project directory " $data " does not exist."; exit 1; fi

if compgen -G $data/*/*/assembly/release/${id}.[0-9]/insdc/GCA*fasta.gz > /dev/null
    then genome=$(ls $data/*/*/assembly/release/${id}.[0-9]/insdc/GCA*fasta.gz | tail -1)
elif compgen -G $data/*/*/assembly/release/${id}.[0-9]_{p,m}aternal_haplotype/insdc/GCA*fasta.gz > /dev/null
    then genome=$(ls $data/*/*/assembly/release/${id}.[0-9]_*aternal_haplotype/insdc/GCA*fasta.gz | tail -1)
else echo "Genome for $id not found in $data"; exit 1; fi

taxon=$(echo $genome | cut -f8 -d'/')
organism=$(echo $genome | cut -f9 -d'/')
assembly=$(echo $genome | cut -f12 -d'/')
gca=$(echo $genome | cut -f14 -d'/' | sed 's/.fasta.gz//')

# Currently this will import a masked file, but once the `insdcdownload` pipeline goes in production, it will be unmasked
gunzip -c $genome > ${gca}.fasta

gdata=$data/$taxon/$organism/genomic_data
analysis=$data/$taxon/$organism/analysis/$assembly

echo "sample,datatype,datafile,library,outdir" > samplesheet.csv
if compgen -G $gdata/*/hic*/*cram > /dev/null
    then reads=($(ls $gdata/*/hic*/*cram))
    datatype="hic"
    for fname in ${reads[@]}
	do sample=$(dirname $fname | cut -f 11 -d'/')
	echo "${sample},${datatype},${fname},,$analysis" >> samplesheet.csv
    done
fi
if compgen -G $gdata/*/illumina*/*cram > /dev/null
    then reads=($(ls $gdata/*/illumina*/*cram))
    datatype="illumina"
    for fname in ${reads[@]}
        do sample=$(dirname $fname | cut -f 11 -d'/')
        echo "${sample},${datatype},${fname},,$analysis" >> samplesheet.csv
    done
fi
if compgen -G $gdata/*/pacbio*/*ccs*bam > /dev/null
    then reads=($(ls $gdata/*/pacbio*/*ccs*bam))
    datatype="pacbio"
    for fname in ${reads[@]}
        do sample=$(dirname $fname | cut -f 11 -d'/')
        echo "${sample},${datatype},${fname},,$analysis" >> samplesheet.csv
    done
fi
if compgen -G $gdata/*/pacbio*/*clr*bam > /dev/null
    then reads=($(ls $gdata/*/pacbio*/*clr*bam))
    datatype="pacbio_clr"
    for fname in ${reads[@]}
        do sample=$(dirname $fname | cut -f 11 -d'/')
        echo "${sample},${datatype},${fname},,$analysis" >> samplesheet.csv
    done
fi
if compgen -G $gdata/*/ont*/*fastq.gz > /dev/null
    then reads=($(ls $gdata/*/ont*/*fastq.gz))
    datatype="ont"
    for fname in ${reads[@]}
        do sample=$(dirname $fname | cut -f 11 -d'/')
        echo "${sample},${datatype},${fname},,$analysis" >> samplesheet.csv
    done
fi
if [[ $(wc -l < samplesheet.csv) -ge 2 ]]
    then :
else echo "No read files."; exit 1; fi
