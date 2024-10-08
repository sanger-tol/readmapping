# sanger-tol/readmapping: Output

## Introduction

This document describes the output produced by the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

The directories comply with Tree of Life's canonical directory structure.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Preprocessing](#preprocessing)
  - [Filtering](#filtering) – Filtering PacBio data before alignment
- [Alignment and Mark duplicates](#alignment-and-mark-duplicates)
  - [Output options](#outfmt) – Output options for all read types
  - [Short reads](#short-reads) – Aligning HiC and Illumina reads using BWAMEM2
  - [Oxford Nanopore reads](#oxford-nanopore-reads) – Aligning ONT reads using MINIMAP2
  - [PacBio reads](#pacbio-reads) – Aligning PacBio CLR and CCS filtered reads using MINIMAP2
- [Alignment post-processing](#alignment-post-processing)
  - [Statistics](#statistics) – Alignment statistics
- [Workflow reporting and genomes](#workflow-reporting-and-genomes)
  - [Reference genome files](#reference-genome-files) - Reference genome indices/files
  - [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

## Preprocessing

### Filtering

PacBio reads generated using both CLR and CCS technology are filtered using `BLAST_BLASTN` against a database of adapter sequences. The collated FASTQ of the filtered reads is required by the downstream alignment step. The results from the PacBio filtering subworkflow are currently not set to output.

## Alignment and Mark duplicates

### Output options

- **outfmt**: Specifies the output format for alignments. It can be set to "bam", "cram", or both, separated by a comma (e.g., `--outfmt bam,cram`). The pipeline will generate output files in the specified formats.
- **compression**: Specifies the compression method for alignments. It can be set to "none" or "crumble". When set to "crumble", the pipeline compresses the quality scores of the alignments.

### Short reads

Short read data from HiC and Illumina technologies is aligned with `BWAMEM2_MEM`. The sorted and merged alignment files are processed using the `SAMTOOLS` [mark-duplicate workflow](https://www.htslib.org/algorithms/duplicate.html#workflow). The marked duplicate alignments are output in the CRAM or BAM format, along with the index.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `hic`
    - `<gca_accession>.unmasked.hic.<sample_id>.[cr|b]am`: Sorted and merged BAM or CRAM file at the individual level
    - `<gca_accession>.unmasked.hic.<sample_id>.[cr|b]am.[cr|c]si`: Index for the alignment (as either .csi or .crai)
  - `illumina`
    - `<gca_accession>.unmasked.illumina.<sample_id>.[cr|b]am`: Sorted and merged BAM or CRAM file at the individual level
    - `<gca_accession>.unmasked.illumina.<sample_id>.[cr|b]am.[cr|c]si`: Index for the alignment

</details>

### Oxford Nanopore reads

Reads generated using Oxford Nanopore technology are aligned with `MINIMAP2_ALIGN`. The sorted and merged alignment is output in the CRAM or BAM format, along with the index.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `ont`
    - `<gca_accession>.unmasked.ont.<sample_id>.[cr|b]am`: Sorted and merged BAM or CRAM file at the individual level
    - `<gca_accession>.unmasked.ont.<sample_id>.[cr|b]am.[cr|c]si`: Index for the alignment

</details>

### PacBio reads

The filtered PacBio reads are aligned with `MINIMAP2_ALIGN`. The sorted and merged alignment is output in the CRAM or BAM format, along with the index.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `pacbio`
    - `<gca_accession>.unmasked.pacbio.<sample_id>.[cr|b]am`: Sorted and merged BAM or CRAM file at the individual level
    - `<gca_accession>.unmasked.pacbio.<sample_id>.[cr|b]am.[cr|c]si`: Index for the alignment

</details>

## Alignment post-processing

### External metadata

If provided using the `--header` option, all output alignments (`*.cram` or `*.bam`) will include any additional metadata supplied as a SAM header template, replacing the existing _@HD_ and _@SD_ entries (note that this behaviour can be altered by modifying the `ext.args` for `SAMTOOLS_REHEADER` in `modules.config`).

### Statistics

The output alignments, along with the index, are used to calculate mapping statistics. Output files are generated using `SAMTOOLS_STATS`, `SAMTOOLS_FLAGSTAT` and `SAMTOOLS_IDXSTATS`.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `hic`
    - `<gca_accession>.unmasked.hic.<sample_id>.stats`: Comprehensive statistics from alignment file
    - `<gca_accession>.unmasked.hic.<sample_id>.flagstat`: Number of alignments for each FLAG type
    - `<gca_accession>.unmasked.hic.<sample_id>.idxstats`: Alignment summary statistics
  - `ont`
    - `<gca_accession>.unmasked.ont.<sample_id>.stats`: Comprehensive statistics from alignment file
    - `<gca_accession>.unmasked.ont.<sample_id>.flagstat`: Number of alignments for each FLAG type
    - `<gca_accession>.unmasked.ont.<sample_id>.idxstats`: Alignment summary statistics
  - `pacbio`
    - `<gca_accession>.unmasked.pacbio.<sample_id>.stats`: Comprehensive statistics from alignment file
    - `<gca_accession>.unmasked.pacbio.<sample_id>.flagstat`: Number of alignments for each FLAG type
    - `<gca_accession>.unmasked.pacbio.<sample_id>.idxstats`: Alignment summary statistics

</details>

## Workflow reporting and genomes

### Reference genome files

A number of genome-specific files are generated by the pipeline because they are required for the downstream processing of the results. These include an unmasked version of the genome by process `UNMASK` and an index by `BWAMEM2_INDEX`. They are currently not set to output.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/readmapping/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
