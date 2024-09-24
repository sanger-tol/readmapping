# sanger-tol/readmapping: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [[1.3.1](https://github.com/sanger-tol/readmapping/releases/tag/1.3.0)] - Antipodean Opaleye - [2024-09-24]

### Enhancements & fixes

- Fixed bug in handling CRAM HiC inputs introduced in 1.1.0
- Fixed bug in handling PacBio FASTQ inputs introduced in 1.3.0

## [[1.3.0](https://github.com/sanger-tol/readmapping/releases/tag/1.3.0)] - Antipodean Opaleye - [2024-08-23]

### Enhancements & fixes

- Combined steps to improve the efficiency of the pipeline, especially on large genomes
- "crumble" is now run on _every_ data type, not just PacBio
- Added options for output format and to turn on/off crumble compression (https://github.com/sanger-tol/readmapping/pull/107)
- Added `fastq` as possible input type for PacBio (https://github.com/sanger-tol/readmapping/pull/106) and Illumina/HiC (https://github.com/sanger-tol/readmapping/pull/96)
- Disabled running `bwa index` when no short-read data provided (https://github.com/sanger-tol/readmapping/pull/100)
- Added support for optional custom SAM header (https://github.com/sanger-tol/readmapping/pull/95)
- Switch to `nf-validation` (https://github.com/sanger-tol/readmapping/pull/99) and further updates for nf-core v2.14 compliance (https://github.com/sanger-tol/readmapping/pull/98)

### Software dependencies

Note, since the pipeline is using Nextflow DSL2, each process will be run with its own [Biocontainer](https://biocontainers.pro/#/registry). This means that on occasion it is entirely possible for the pipeline to be using different versions of the same tool. However, the overall software dependency changes compared to the last release have been listed below for reference.

| Dependency | Old version   | New version |
| ---------- | ------------- | ----------- |
| `blastn`   | 2.13          | 2.15        |
| `minimap2` | 2.24          | 2.28        |
| `samtools` | 1.14 and 1.17 | 1.20        |
| `seqkit`   |               | 2.8.1       |
| `seqtk`    |               | 1.4         |

> **NB:** Dependency has been **updated** if both old and new version information is present. </br> **NB:** Dependency has been **added** if just the new version information is present. </br> **NB:** Dependency has been **removed** if version information isn't present.

### Parameters

| Old parameter | New parameter  |
| ------------- | -------------- |
|               | '--header'     |
|               | '--outfmt'     |
|               | '--compression |

> **NB:** Parameter has been **updated** if both old and new parameter information is present. </br> **NB:** Parameter has been **added** if just the new parameter information is present. </br> **NB:** Parameter has been **removed** if new parameter information isn't present.

## [[1.2.2](https://github.com/sanger-tol/readmapping/releases/tag/1.2.2)] - Norwegian Ridgeback (patch 2) - [2024-05-23]

### Enhancements & fixes

- Fixed the bug in the filtering of multiple PacBio files

## [[1.2.1](https://github.com/sanger-tol/readmapping/releases/tag/1.2.1)] - Norwegian Ridgeback (patch 1) - [2024-02-29]

### Enhancements & fixes

- Increased the memory requests for reruns of BWAMEM2_MEM and SAMTOOLS_SORMADUP.

## [[1.2.0](https://github.com/sanger-tol/readmapping/releases/tag/1.2.0)] – Norwegian Ridgeback - [2023-12-19]

### Enhancements & fixes

- Restored recording read-groups (`@RG`) in the BAM/CRAM files.
- Updated the CI procedure to use "sanger-tol" rather than "nf-core" names.
- [crumble](https://github.com/jkbonfield/crumble) now used to compress the
  PacBio HiFi alignments.
- Execution statistics now under `pipeline_info/readmapping/` (to be consistent
  with the other sanger-tol pipelines).
- All resource requirements (memory, time, CPUs) now fit the actual usage. This
  is achieved by automatically adjusting to the size of the input whenever
  possible.
- Added the `--use_work_dir_as_temp` parameter to make SAMTOOLS_COLLATE use its
  work directory for temporary files instead of `$TMPDIR`. It can be used to avoid
  leaving unwanted temporary files on a HPC.

### Parameters

| Old parameter | New parameter            |
| ------------- | ------------------------ |
|               | `--use_work_dir_as_temp` |

> **NB:** Parameter has been **updated** if both old and new parameter information is present. </br> **NB:** Parameter has been **added** if just the new parameter information is present. </br> **NB:** Parameter has been **removed** if new parameter information isn't present.

### Software dependencies

Note, since the pipeline is using Nextflow DSL2, each process will be run with its own [Biocontainer](https://biocontainers.pro/#/registry). This means that on occasion it is entirely possible for the pipeline to be using different versions of the same tool. However, the overall software dependency changes compared to the last release have been listed below for reference.

| Dependency | Old version     | New version   |
| ---------- | --------------- | ------------- |
| `blast`    | 2.12.0          | 2.13.0        |
| `crumble`  |                 | 0.9.1         |
| `samtools` | 1.14 and 1.16.1 | 1.14 and 1.17 |
| `multiqc`  | 1.13            | 1.14          |

> **NB:** Dependency has been **updated** if both old and new version information is present. </br> **NB:** Dependency has been **added** if just the new version information is present. </br> **NB:** Dependency has been **removed** if version information isn't present.

## [[1.1.0](https://github.com/sanger-tol/readmapping/releases/tag/1.1.0)] – Hebridean Black - [2023-03-16]

### Enhancements & fixes

- Bump minimum Nextflow version from `22.04.0` -> `22.10.1`
- Updated pipeline template to [nf-core/tools 2.7.1](https://github.com/nf-core/tools/releases/tag/2.7.1)
- Added nf-core modules to replace most local modules
- Added improved resource settings
- Added support for unit and full tests on Sanger HPC via Nextflow Tower
- Added all unit test data on a S3 bucket
- Added statistics subworkflow functionality to the alignment subworkflows
- Removed support for iGenomes
- Removed samtools faidx and minimap index module, it now happens on the fly

### Parameters

| Old parameter      | New parameter |
| ------------------ | ------------- |
| `--enable_conda`   |               |
| `--minimap2_index` |               |
| `--samtools_index` |               |

> **NB:** Parameter has been **updated** if both old and new parameter information is present. </br> **NB:** Parameter has been **added** if just the new parameter information is present. </br> **NB:** Parameter has been **removed** if new parameter information isn't present.

### Software dependencies

Note, since the pipeline is using Nextflow DSL2, each process will be run with its own [Biocontainer](https://biocontainers.pro/#/registry). This means that on occasion it is entirely possible for the pipeline to be using different versions of the same tool. However, the overall software dependency changes compared to the last release have been listed below for reference.

| Dependency  | Old version     | New version     |
| ----------- | --------------- | --------------- |
| `minimap2`  | 2.21            | 2.24            |
| `samtools`  | 1.15 and 1.15.1 | 1.14 and 1.16.1 |
| `multiqc`   | 1.11 and 1.12   | 1.13            |
| `bam2fastx` | 1.3.1           |                 |
| `pbbam`     | 2.1.0           |                 |

> **NB:** Dependency has been **updated** if both old and new version information is present. </br> **NB:** Dependency has been **added** if just the new version information is present. </br> **NB:** Dependency has been **removed** if version information isn't present.

## [[v1.0.0](https://github.com/sanger-tol/readmapping/releases/tag/1.0.0)] – Ukrainian Ironbelly - [2022-05-19]

Initial release of sanger-tol/readmapping, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- HiC and Illumina read alignment to genome
- PacBio CLR and CCS read alignment to genome after filtering
- Nanopore read alignment to genome
- Mark duplicates for HiC and Illumina alignments
- Convert to CRAM and calculate statistics for all alignments

### `Fixed`

### `Dependencies`

- `nextflow`
- `singularity` or `docker`

### `Deprecated`
