#!/bin/bash

input=$1
output=$2

grep -v 'MG551957' $input | awk -v OFS='\t' '{if (($6 ~ /NGB00972/ && $10/$11 >= 0.97 && $10 >= 44) || ($6 ~ /NGB00973/ && $10/$11 >= 0.97 && $10 >= 34) || ($6 ~ /^bc/ && $10/$11 >= 0.99 && $10 >= 16)) print $1}' | sort -u > $output
