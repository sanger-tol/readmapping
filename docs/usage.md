# sanger-tol/readmapping: Usage

## :warning: Please read this documentation on the sanger-tol/readmapping wiki: [https://github.com/sanger-tol/readmapping/wiki/Usage](https://github.com/sanger-tol/readmapping/wiki/Usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Use this parameter to specify its location. It has to be a comma-separated file with 4 columns, and a header row as shown in the examples below.

```console
--input '[path to samplesheet file]'
```

### Multiple runs of the same sample

The `sample` identifiers have to be the same when you have re-sequenced the same sample more than once e.g. to increase sequencing depth. The pipeline will analyse each library individually and then merge them by datatype before performing downstream analysis. Below is an example for the same sample sequenced across 3 lanes of HiC:

```console
sample,datatype,datafile,library
sample1,hic,hic1.cram,lib1
sample1,hic,hic2.cram,lib2
sample1,hic,hic3.cram,lib3
```

### Full samplesheet

The samplesheet can have as many columns as you desire, however, there is a strict requirement for the first 4 columns to match those defined in the table below.

A final samplesheet file consisting of both HiC and PacBio data may look something like the one below.

```console
sample,datatype,datafile,library
sample1_T1,hic,hic1.cram,lib1
sample1_T2,hic,hic2.cram,lib2
sample1_T3,hic,hic3.cram,lib3
sample1_T4,pacbio,pacbio1.bam,pacbio1
sample1_T5,pacbio,pacbio2.bam,pacbio2
```

| Column     | Description |
|------------|-------------|
| `sample`   | Custom sample name. This entry will be identical for multiple sequencing libraries/runs from the same sample. Spaces in sample names are automatically converted to underscores (_). |
| `datatype` | Type of sequencing data. Must be one of `hic`, `Illumina`, `pacbio`, or `ont`. |
| `datafile` | Full path to read data file. Must be `bam` or `cram` for `hic` and `illumina`. Must be `bam` for `pacbio`. Must be `fastq.gz` or `fq.gz` for `ont`. |
| `library`  | (Optional) The library value is a unique identifier which is assigned to read group (`@RG`) ID. If the library name is not specified, the pipeline will auto-create library name using the data filename provided in the samplesheet. |

An [example samplesheet](https://github.com/sanger-tol/readmapping/blob/main/test/samplesheet.csv) has been provided with the pipeline.

## Running the pipeline

The typical command for running the pipeline is as follows:

```console
nextflow run sanger-tol/readmapping --input samplesheet.csv --outdir <OUTDIR> --fasta genome.fa.gz -profile singularity
```

This will launch the pipeline with the `singularity` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```console
work            # Directory containing the nextflow working files
results         # Finished results (configurable, see below)
.nextflow_log   # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```console
nextflow pull sanger-tol/readmapping
```

### Reproducibility

It is a good idea to specify a pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [sanger-tol/readmapping releases page](https://github.com/sanger-tol/readmapping/releases) and find the latest version number - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future.

## Core Nextflow arguments

> **NB:** These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen).

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Conda) - see below. When using Biocontainers, most of these software packaging methods pull Docker containers from quay.io e.g [FastQC](https://quay.io/repository/biocontainers/fastqc) except for Singularity which directly downloads Singularity images via https hosted by the [Galaxy project](https://depot.galaxyproject.org/singularity/) and Conda which downloads and installs software locally from [Bioconda](https://bioconda.github.io/).

> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to see if your system is available in these configs please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended.

* `docker`
    * A generic configuration profile to be used with [Docker](https://docker.com/)
* `singularity`
    * A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
* `podman`
    * A generic configuration profile to be used with [Podman](https://podman.io/)
* `shifter`
    * A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
* `charliecloud`
    * A generic configuration profile to be used with [Charliecloud](https://hpc.github.io/charliecloud/)
* `conda`
    * A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter or Charliecloud.
* `test`
    * A profile with a complete configuration for automated testing
    * Includes links to test data so needs no other parameters

### `-resume`

Specify this when restarting a pipeline. Nextflow will used cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously.

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the steps in the pipeline, if the job exits with any of the error codes specified [here](https://github.com/sanger-tol/readmapping/blob/b74462de9d288d418c0b2724a9ddceec10a0d604/conf/base.config#L18) it will automatically be resubmitted with higher requests (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

For example, if the sanger-tol/readmapping pipeline is failing after multiple re-submissions of the `BWAMEM2_MEM` process due to an exit code of `137` this would indicate that there is an out of memory issue. To bypass this error you would need to find exactly which resources are set by the `BWAMEM2_MEM` process. The quickest way is to search for `process BWAMEM2_MEM` in the [sanger-tol/readmapping Github repo](https://github.com/sanger-tol/readmapping). We have standardised the structure of Nextflow DSL2 pipelines such that all module files will be present in the `modules/` directory and so, based on the search results, the file we want is `modules/nf-core/modules/bwamem2/mem/main.nf`. If you click on the link to that file you will notice that there is a `label` directive at the top of the module that is set to [`label process_high`](https://github.com/sanger-tol/readmapping/blob/b74462de9d288d418c0b2724a9ddceec10a0d604/modules/nf-core/modules/bwamem2/mem/main.nf#L3). The [Nextflow `label`](https://www.nextflow.io/docs/latest/process.html#label) directive allows us to organise workflow processes in separate groups which can be referenced in a configuration file to select and configure subset of processes having similar computing requirements. The default values for the `process_high` label are set in the pipeline's [`base.config`](https://github.com/sanger-tol/readmapping/blob/main/conf/base.config) which in this case is defined as 72GB. Providing you haven't set any other standard nf-core parameters to cap the [maximum resources](https://nf-co.re/usage/configuration#max-resources) used by the pipeline then we can try and bypass the `BWAMEM2_MEM` process failure by creating a custom config file that sets at least 72GB of memory, in this case increased to 100GB. The custom config below can then be provided to the pipeline via the [`-c`](https://github.com/sanger-tol/readmapping/wiki/Usage#-c) parameter as highlighted in previous sections.

```nextflow
process {
    withName: 'NFCORE_READMAPPING:READMAPPING:ALIGN_HIC:BWAMEM2_MEM' {
        memory = 100.GB
    }
}
```

> **NB:** We specify the full process name i.e. `NFCORE_READMAPPING:READMAPPING:ALIGN_HIC:BWAMEM2_MEM` in the config file because this takes priority over the short name (`BWAMEM2_MEM`) and allows existing configuration using the full process name to be correctly overridden.
> If you get a warning suggesting that the process selector isn't recognised check that the process name has been specified correctly.

### Updating containers

The [Nextflow DSL2](https://www.nextflow.io/docs/latest/dsl2.html) implementation of this pipeline uses one container per process which makes it much easier to maintain and update software dependencies. If for some reason you need to use a different version of a particular tool with the pipeline then you just need to identify the `process` name and override the Nextflow `container` definition for that process using the `withName` declaration. For example, in the [nf-core/viralrecon](https://nf-co.re/viralrecon) pipeline a tool called [Pangolin](https://github.com/cov-lineages/pangolin) has been used during the COVID-19 pandemic to assign lineages to SARS-CoV-2 genome sequenced samples. Given that the lineage assignments change quite frequently it doesn't make sense to re-release the nf-core/viralrecon everytime a new version of Pangolin has been released. However, you can override the default container used by the pipeline by creating a custom config file and passing it as a command-line argument via `-c custom.config`.

1. Check the default version used by the pipeline in the module file for [Pangolin](https://github.com/nf-core/viralrecon/blob/a85d5969f9025409e3618d6c280ef15ce417df65/modules/nf-core/software/pangolin/main.nf#L14-L19)
2. Find the latest version of the Biocontainer available on [Quay.io](https://quay.io/repository/biocontainers/pangolin?tag=latest&tab=tags)
3. Create the custom config accordingly:

    * For Docker:

        ```nextflow
        process {
            withName: PANGOLIN {
                container = 'quay.io/biocontainers/pangolin:3.0.5--pyhdfd78af_0'
            }
        }
        ```

    * For Singularity:

        ```nextflow
        process {
            withName: PANGOLIN {
                container = 'https://depot.galaxyproject.org/singularity/pangolin:3.0.5--pyhdfd78af_0'
            }
        }
        ```

    * For Conda:

        ```nextflow
        process {
            withName: PANGOLIN {
                conda = 'bioconda::pangolin=3.0.5'
            }
        }
        ```

> **NB:** If you wish to periodically update individual tool-specific results (e.g. Pangolin) generated by the pipeline then you must ensure to keep the `work/` directory otherwise the `-resume` ability of the pipeline will be compromised and it will restart from scratch.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```console
NXF_OPTS='-Xms1g -Xmx4g'
```
