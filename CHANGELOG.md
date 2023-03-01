# sanger-tol/readmapping: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 – Hebridean Black - [2023-mm-dd]

A cleaner and more efficient implementation of the pipeline.

### `Added`

– Updated pipeline template to [nf-core/tools v2.7.1](https://github.com/nf-core/tools/releases/tag/2.7.1)
– Improved resource settings
– Full and unit testing on Sanger farm directly from GitHub

### `Fixed`

– Genome indexing now happens on the fly
– Most modules are now from nf-core instead of local
– Merge statistics subworkflow functionality merged into the main alignment subworkflow

### `Dependencies`

### `Deprecated`

– Full and unit testing on AWS
– All instances of MultiQC and FastQC have been removed

## v1.0.0 – Ukrainian Ironbelly - [2022-05-19]

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
