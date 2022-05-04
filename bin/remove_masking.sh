#!/bin/bash

fasta=$1
output=${fasta%.*}.unmasked.fasta

awk 'BEGIN{FS=" "}{if(!/>/){print toupper($0)}else{print $0}}' $fasta > $output
