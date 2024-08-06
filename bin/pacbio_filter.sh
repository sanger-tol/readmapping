#!/bin/bash

input=$1
output=$2

awk -v OFS='\t' '{if (($6 ~ /NGB00972/ && $11 >= 97 && $10 >= 44) || ($6 ~ /NGB00973/ && $11 >= 97 && $10 >= 34) || ($6 ~ /^bc/ && $11 >= 99 && $10 >= 16)) print $1}' $input | sort -u > $output
