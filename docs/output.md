# sanger-tol/readmapping: Output

## Introduction

This document describes the output produced by the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

The directories comply with Tree of Life's canonical directory structure.

## Pipeline overview

### Process overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Quality control](#quality-control) - Check quality of input reads before and after filtering with FASTQC
- [Preprocessing](#preprocessing)
  - [ULI preprocessing](#uli_preprocessing)
    - Demultiplexing and trimming ULI adapters with LIMA
    - Mark duplicates with PBMARKDUP
  - [Filtering](#filtering) – Filtering PacBio data before alignment with HIFI_TRIMMER
- [Alignment and Mark duplicates](#alignment-and-mark-duplicates)
  - [Output options](#output-options) – Output options for all read types
  - [Short reads](#short-reads) – Aligning HiC and Illumina reads using BWAMEM2 (by default) or MINIMAP2
  - [Oxford Nanopore reads](#oxford-nanopore-reads) – Aligning ONT reads using MINIMAP2
  - [PacBio reads](#pacbio-reads) – Aligning PacBio CLR and CCS filtered reads using MINIMAP2
- [Alignment post-processing](#alignment-post-processing)
  - [Merge by speciemen](#merge-by-speciment) - Merge aligned reads by specimens
  - [External metadata](#external-metadata) – Additional metadata in alignments
  - [Read coverage](#read-coverage) – Read coverage calculations
  - [Statistics](#statistics) – Alignment statistics
- [Workflow reporting](#workflow-reporting)
  - [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution
  - [MultiQC report](#multiqc-report) – Combined input/output QC summary

### Output overview

- `pipeline_info` - execution information of run
- `read_mapping`
- `${datatype}/${specimen}`
  - `${run}/`
    - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.cram`: Aligned CRAM file (or `.bam` depending on `--outfmt`)
    - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.cram.crai`: Index for the alignment
    - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.coverage.bedGraph.gz`: Read coverage in bedGraph format
    - `qc/`
      - `${datatype}.${specimen}.${run}.fastqc.html`: FASTQC report of reads
      - `${datatype}.${specimen}.${run}.fastqc.zip`: FASTQC archive of reads
      - `pacbio.${specimen}.${run}.rmdup.pbmarkdup.log`: if `library: uli`, PBMARKDUP report of markduplicated PacBio reads (optional)
      - `pacbio.${specimen}.${run}.lima.report`: if `library: uli`, LIMA report of adapter trimming and demultiplexing (optional)
      - `pacbio.${specimen}.${run}.filtered.fastqc.html`: FASTQC report of filtered reads (optional, if filtered reads)
      - `pacbio.${specimen}.${run}.filtered.fastqc.zip`: FASTQC archive of filtered reads (optional, if filtered reads )
      - `pacbio.${specimen}.${run}.hifitrimmer.bed.gz`: HiFi trimmer trimming regions (optional, if filtered reads)
      - `pacbio.${specimen}.${run}.hifitrimmer.summary.json`: HiFi trimmer trimming summary (optional, if filtered reads)
    - `stats/`
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.flagstat`: Number of alignments for each FLAG type
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.idxstats`: Alignment summary statistics
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.stats.gz`: Comprehensive statistics
  - `merged.${#}/` (optional if `params.merged_output` is specified)
    - `${assembly}.${datatype}.${specimen}.merged.${#}.${aligner}.cram`: Merged aligned CRAM file
    - `${assembly}.${datatype}.${specimen}.merged.${#}.${aligner}.cram.crai`: Index for the merged alignment
    - `${assembly}.${datatype}.${specimen}.merged.${#}.${aligner}.coverage.bedGraph.gz`: Read coverage for merged file
    - `stats/`
      - `${assembly}.${datatype}.${specimen}.merged.${#}.${aligner}.flagstat`: Number of alignments for each FLAG type
      - `${assembly}.${datatype}.${specimen}.merged.${#}.${aligner}.idxstats`: Merged alignment summary statistics
  - `merged_${#}/` (optional if `params.merged_output` is specified)
    - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.cram`: Merged aligned CRAM file
    - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.cram.crai`: Index for the merged alignment
    - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.coverage.bedGraph.gz`: Read coverage for merged file
    - `stats/`
      - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.flagstat`: Number of alignments for each FLAG type
      - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.idxstats`: Merged alignment summary statistics
      - `${assembly}.${datatype}.${specimen}.merged_${#}.${aligner}.stats.gz`: Comprehensive statistics for merged alignment
  - `multiqc_report.html`: Interactive HTML report summarizing quality metrics from FastQC, alignment statistics, and other quality control data across all samples

## Preprocessing

### Quality Control

Input files undergo quality assessment using FASTQC, a widely-used tool for evaluating raw sequencing data. If the input is in CRAM format, it is first converted to FASTQ format to enable compatibility with FASTQC.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping/${datatype}/${specimen}/${run}/qc/`
  - `${datatype}.${specimen}.${run}.fastqc.html`: An interactive HTML report summarizing key read quality metrics
  - `${datatype}.${specimen}.${run}.fastqc.zip`: A compressed archive containing the full set of FASTQC output files

</details>

### ULI preprocessing

PacBio ULI read (`library`:`uli`) are demultiplexed with LIMA and mark duplicated with PBMARKDUP.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping/pacbio/${specimen}/${run}/qc/`
  - `pacbio.${specimen}.${run}.pbmarkdup.log`: BED format file with trimming coordinates
  - `pacbio.${specimen}.${run}.lima.report`: Statistics of demultiplexing & ULI adpater trimming

</details>

### Filtering

PacBio reads generated using both CLR and CCS technology are filtered using `HIFITRIMMER`. Additional quality control is performed to check the filtered reads.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping/pacbio/${specimen}/${run}/qc/`
  - `pacbio.${specimen}.${run}.hifitrimmer.bed.gz`: BED format file with trimming coordinates
  - `pacbio.${specimen}.${run}.hifitrimmer.summary.json`: Summary statistics of trimming results
  - `pacbio.${specimen}.${run}.filtered.fastqc.html`: FASTQC report of filtered reads
  - `pacbio.${specimen}.${run}.filtered.fastqc.zip`: FASTQC archive of filtered reads

</details>

## Alignment and Mark duplicates

This section documents the output files from alignment and duplicate marking steps of the pipeline. These files are generated after the Preprocessing step completes.

### Output options

- **outfmt**: Specifies the output format for alignments. It can be set to "bam", "cram", or both, separated by a comma (e.g., `--outfmt bam,cram`). The pipeline will generate output files in the specified formats.
- **compression**: Specifies the compression method for alignments. It can be set to "none" or "crumble". When set to "crumble", the pipeline compresses the quality scores of the alignments.
- **merge_output**: Merge output at the individual level. If merge_output is enabled (default: false), both unmerged and merged output files per sample will be generated; otherwise, only unmerged files are exported.

### Short reads

Short read data from HiC and Illumina technologies is aligned with `BWAMEM2_MEM` (by default) or `MINIMAP2`. The sorted alignment files are processed using the `SAMTOOLS` [mark-duplicate workflow](https://www.htslib.org/algorithms/duplicate.html#workflow). The marked duplicate alignments are output in the CRAM or BAM format.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `${datatype}/${specimen}`
    - `${run}/`
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.cram`: Aligned CRAM file (or `.bam` depending on `--outfmt`)
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.cram.crai`: Index for the alignment
      - `${assembly}.${datatype}.${specimen}.${run}.${aligner}.coverage.bedGraph.gz`: Read coverage in bedGraph format
    - `merged.${#}/` - if params `merge_output`, merged output files with same structure as individual runs, without `qc` folder

</details>

### Oxford Nanopore reads

Reads generated using Oxford Nanopore technology are aligned with `MINIMAP2_ALIGN`. The sorted alignment is output in the CRAM or BAM format.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `ont/${specimen}`
    - `${run}/`
      - `${assembly}.ont.${specimen}.${run}.${aligner}.cram`: Aligned CRAM file (or `.bam` depending on `--outfmt`)
      - `${assembly}.ont.${specimen}.${run}.${aligner}.cram.crai`: Index for the alignment
      - `${assembly}.ont.${specimen}.${run}.${aligner}.coverage.bedGraph.gz`: Read coverage in bedGraph format
    - `merged_${#}/` - if params `merge_output`.
  </details>

### PacBio reads

The filtered PacBio reads are aligned with `MINIMAP2_ALIGN`. The sorted alignment is output in the CRAM or BAM format.

<details markdown="1">
<summary>Output files</summary>

- `read_mapping`
  - `pacbio/${specimen}`
    - `${run}/`
      - `${assembly}.pacbio.${specimen}.${run}.${aligner}.cram`: Aligned CRAM file (or `.bam` depending on `--outfmt`)
      - `${assembly}.pacbio.${specimen}.${run}.${aligner}.cram.crai`: Index for the alignment
      - `${assembly}.pacbio.${specimen}.${run}.${aligner}.coverage.bedGraph.gz`: Read coverage in bedGraph format
    - `merged_${#}/` - if params `merge_output`.

</details>

## Alignment post-processing

### External metadata

If provided using the `--header` option, all output alignments (`*.cram` or `*.bam`) will include any additional metadata supplied as a SAM header template, replacing the existing _@HD_ and _@SD_ entries (note that this behaviour can be altered by modifying the `ext.args` for `SAMTOOLS_REHEADER` in `modules.config`).

### Read coverage

Read coverage of the output alignment file is calculated with [blobtk depth](https://github.com/genomehubs/blobtk/wiki/blobtk-depth) and output alongside the alignment files.

**File naming:** `${assembly}.${type}.${specimen}.${run}.${aligner}.coverage.bedGraph.gz`

### Statistics

The output alignments are used to calculate mapping statistics. Output files are generated using `SAMTOOLS_STATS`, `SAMTOOLS_FLAGSTAT` and `SAMTOOLS_IDXSTATS` and are organized in `stats/` subdirectories of each run or merged specimen:

**File naming:**

- `${assembly}.${datatype}.${specimen}.${run}.${aligner}.flagstat`: Number of alignments for each FLAG type
- `${assembly}.${datatype}.${specimen}.${run}.${aligner}.idxstats`: Alignment summary statistics
- `${assembly}.${datatype}.${specimen}.${run}.${aligner}.stats.gz`: Comprehensive statistics

For merged output (when `merge_output` is enabled), replace `${run}` with `merged.${#}` in the filenames.

## Workflow reporting

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - `execution_report_<timestamp>.html`: Nextflow execution report
  - `execution_timeline_<timestamp>.html`: Nextflow execution timeline visualization
  - `execution_trace_<timestamp>.txt`: Nextflow execution trace with resource usage details
  - `pipeline_dag_<timestamp>.html`: Pipeline DAG (Directed Acyclic Graph) visualization
  - `params_<timestamp>.json`: Parameters used in the pipeline run
  - `readmapping_software_mqc_versions.yml`: Software versions used in the workflow

### MultiQC report

The workflow generates a MultiQC summary report that aggregates and visualises statistics (e.g., FastQC, alignment statistics).

<details markdown="1">
<summary>Output files</summary>

- `multiqc_report.html`: Interactive HTML report summarizing quality metrics from FastQC, alignment statistics, and other quality control data across all samples

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
