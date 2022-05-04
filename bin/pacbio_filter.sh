#!/bin/bash

input=$1
output=$2

grep -v 'MG551957' $input | awk -v OFS='\t' '{if (($2 ~ /NGB00972/ && $3 >= 97 && $4 >= 44) || ($2 ~ /NGB00973/ && $3 >= 97 && $4 >= 34) || ($2 ~ /^bc/ && $3 >= 99 && $4 >= 16)) print $1}' | sort -u > $output

