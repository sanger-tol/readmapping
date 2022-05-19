# sanger-tol/readmapping: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0 - [2022-05-19]

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
