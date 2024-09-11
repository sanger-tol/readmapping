#!/bin/bash

# generate_cram_csv.sh
# -------------------
# Generate a csv file describing the CRAM folder
# ><((((°>    Y    ><((((°>    U     ><((((°>    M     ><((((°>     I     ><((((°>
# Author = yy5
# ><((((°>    Y    ><((((°>    U     ><((((°>    M     ><((((°>     I     ><((((°>

# NOTE: chunk_size is the number of containers per chunk (not records/reads)

# Function to process chunking of a CRAM file

chunk_cram() {
    local cram=$1
    local chunkn=$2
    local outcsv=$3
    local crai=$4
    local chunk_size=$5

    local rgline=$(samtools view -H "${realcram}" | grep "@RG" | sed 's/\t/\\t/g' | sed "s/'//g")
    local ncontainers=$(zcat "${realcrai}" | wc -l)
    local base=$(basename "${realcram}" .cram)
    local from=0
    local to=$((chunk_size - 1))

    while [ $to -lt $ncontainers ]; do
        echo "chunk $chunkn: $from - $to"
        echo "${realcram},${realcrai},${from},${to},${base},${chunkn},${rgline}" >> $outcsv
        from=$((to + 1))
        to=$((to + chunk_size))
        ((chunkn++))
    done

    # Catch any remainder
    if [ $from -lt $ncontainers ]; then
        to=$((ncontainers - 1))
        echo "chunk $chunkn: $from - $to"
        echo "${realcram},${realcrai},${from},${to},${base},${chunkn},${rgline}" >> $outcsv
        ((chunkn++))
    fi
}

# Function to process a CRAM file
process_cram_file() {
    local cram=$1
    local chunkn=$2
    local outcsv=$3
    local crai=$4
    local chunk_size=$5

    local read_groups=$(samtools view -H "$cram" | grep '@RG' | awk '{for(i=1;i<=NF;i++){if($i ~ /^ID:/){print substr($i,4)}}}')
    local num_read_groups=$(echo "$read_groups" | wc -w)
    if [ "$num_read_groups" -gt 1 ]; then
        # Multiple read groups: process each separately
        for rg in $read_groups; do
            local output_cram="$(basename "${cram%.cram}")_output_${rg}.cram"
            samtools view -h -r "$rg" -o "$output_cram" "$cram"
            #chunkn=$(chunk_cram "$output_cram" "$chunkn" "$outcsv" "$crai" "$chunk_size")
            chunk_cram "$output_cram" "$chunkn" "$outcsv" "$crai" "$chunk_size"
        done
    else
        # Single read group or no read groups
        #chunkn=$(chunk_cram "$cram" "$chunkn" "$outcsv" "$crai" "$chunk_size")
        chunk_cram "$cram" "$chunkn" "$outcsv" "$crai" "$chunk_size"
    fi
}

#  /\_/\        /\_/\
# ( o.o ) main ( o.o )
#  > ^ <        > ^ <

# Check if cram_path is provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 <cram_path> <output_csv> <crai_file> <chunk_size>"
    exit 1
fi

cram=$1
outcsv=$2
crai=$3
if [ -z "$4" ]; then
    chunk_size=10000
else
    chunk_size=$4
fi
chunkn=0

# Operates on a single CRAM file
realcram=$(readlink -f $cram)
realcrai=$(readlink -f $crai)
if [ -f "$outcsv" ]; then
    rm "$outcsv"
fi
process_cram_file $realcram $chunkn $outcsv $realcrai $chunk_size
