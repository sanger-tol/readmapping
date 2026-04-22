# sanger-tol/readmapping: Usage

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

This pipeline aligns raw reads from various technolgies (such as HiC, Illumina, ONT, PacBio CCS, and PacBio CLR) to the reference genome. It marks duplicates for the short read alignments (HiC and Illumina). Standard statistics are calculated for all aligned data.

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Use this parameter to specify its location. It has to be a comma-separated file with 4 columns, and a header row as shown in the examples below.

```bash
--input '[path to samplesheet file]'
```

### Multiple runs of the same sample

The `sample` identifiers have to be the same when you have re-sequenced the same sample more than once e.g. to increase sequencing depth. The pipeline will analyse the raw reads individually and then merge them by sample and datatype, before performing any downstream analysis. Below is an example for the same sample sequenced across 3 lanes of HiC:

```console
specimen,run,datatype,datafile,library
specimen1,run1,hic,hic1.cram,
specimen1,run2,hic,hic2.cram,
specimen2,run1,hic,hic3.cram,
```

### Full samplesheet

The samplesheet can have as many columns as you desire, however, there is a strict requirement for the first 4 columns to match those defined in the table below.

A final samplesheet file consisting of both HiC and PacBio data may look something like the one below.

```console
specimen,run,datatype,datafile,library
specimen1,run1,hic1.cram,
specimen1,run2,hic2.cram,
specimen2,run3,hic3.cram,
specimen2,run4,pacbio,pacbio1.bam,uli
specimen3,run5,pacbio,pacbio2.bam,
```

| Column     | Description                                                                                                                                                                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `specimen` | Identifier of the specimen. Usually a BioSpecimen accession, i,e. `SAMEA7521529`.                                                                                                                                                           |
| `run`      | Identifier of the sequencing run. Usually the accession number of the data in INSDC. For example,`ERR9248445` (hic), `ERR9284044` (pacbio).                                                                                                 |
| `datatype` | Type of sequencing data. Must be one of `hic`, `illumina`, `pacbio`, `pacbio_clr`, or `ont`.                                                                                                                                                |
| `datafile` | Full path to read data file. Must be `bam`, `cram`, `fastq.gz` or `fq.gz` for `illumina` and `hic`. Must be `bam`, `fastq.gz` or `fq.gz` for `pacbio`, `pacbio_clr`, and `ont`. Note that FASTQ inputs should be interleaved if paired-end. |
| `library`  | (Optional) The library value is a unique identifier which is assigned to read group (`@RG`) ID. If the library name is not specified, the pipeline will auto-create library name using the data filename provided in the samplesheet.       |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run sanger-tol/readmapping --input samplesheet.csv --fasta genome.fa.gz --outdir <OUTDIR> -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

You can also optionally supply a template SAM header using the `--header` option to add or modify metadata associated with the assembly, which will be incorporated into the output alignments.

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run sanger-tol/readmapping -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: './samplesheet.csv'
outdir: './results/'
<...>
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull sanger-tol/readmapping
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [sanger-tol/readmapping releases page](https://github.com/sanger-tol/readmapping/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most pipeline steps, if a job exits with one of the retryable error codes defined in this pipeline's [`conf/base.config`](../conf/base.config), it will automatically be resubmitted with increased resource requests. In most cases these increases scale with `task.attempt`, so the exact increase depends on the process definition rather than being limited to fixed 2x and 3x bumps. The pipeline is configured with `maxRetries = 5`, meaning that after the initial submission a task can be retried up to 5 times (6 total attempts) before pipeline execution is stopped.

For example, if the sanger-tol/readmapping pipeline is failing after multiple re-submissions of the BWA-MEM2 alignment process due to an exit code of `137` this often indicates that the task was killed, commonly due to an out of memory issue. Check the `.command.err` file and any scheduler logs to confirm the exact cause.

#### For beginners

A first step to bypass this error, you could try to increase the amount of CPUs, memory, and time for the whole pipeline. Therefore you can try to increase the resourceLimits, i.e:

```nextflow
process {
  resourceLimits = [
    cpus: 32,
    memory: 256.GB,
    time: 24.h
  ]
}
```

For more information, please see the [resource configuration](https://nf-co.re/docs/running/configuration/nextflow-for-your-system) in the nf-core website.

#### Advanced option on process level

To bypass this error you first need to check which resources are set for the Hi-C BWA-MEM2 alignment step in this pipeline. In `readmapping` this is handled by the local process `CRAMALIGN_BWAMEM2ALIGNHIC` in `modules/sanger-tol/cramalign/bwamem2alignhic/main.nf`, which is labelled [`process_high`](https://github.com/sanger-tol/readmapping/blob/main/modules/sanger-tol/cramalign/bwamem2alignhic/main.nf#L3). The actual resource settings are then overridden in [`conf/base.config`](https://github.com/sanger-tol/readmapping/blob/main/conf/base.config), where the full selector `.*:ALIGN_SHORT:.*:CRAMALIGN_BWAMEM2ALIGNHIC` sets `cpus = 16`, `time = 4.h * task.attempt`, and `memory = 50.GB` for references smaller than 2 Gb or approximately `20.GB` per Gb of reference for larger genomes, scaled by retry attempt. If that still is not sufficient for your data, you can provide a custom config file via the [`-c`](#-c) parameter to override the process-level memory setting, for example increasing it to 100 GB as shown below.

```nextflow
process {
    withName: ".*:ALIGN_SHORT:.*:CRAMALIGN_BWAMEM2ALIGNHIC"  {
      memory = 100.GB
    }
}
```

> **NB:** We specify the full process name i.e. `.*:ALIGN_SHORT:.*:CRAMALIGN_BWAMEM2ALIGNHIC` in the config file because this takes priority over the short process name (`CRAMALIGN_BWAMEM2ALIGNHIC`) and allows existing configuration using the full process name to be correctly overridden.
>
> If you get a warning suggesting that the process selector isn't recognised check that the process name has been specified correctly.

### Custom Containers (advanced users)

The [Nextflow DSL2](https://www.nextflow.io/docs/latest/dsl2.html) implementation of this pipeline uses one container per process which makes it much easier to maintain and update software dependencies. If for some reason you need to use a different version of a particular tool with the pipeline then you just need to identify the `process` name and override the Nextflow `container` definition for that process using the `withName` declaration. You can override the default container used by the pipeline by creating a custom config file and passing it as a command-line argument via `-c custom.config`.

1. Check the default version used by the pipeline in the module file for [Samtools](https://github.com/sanger-tol/readmapping/blob/main/modules/nf-core/samtools/view/main.nf#L5-L8)
2. Find the latest version of the Biocontainer available on [Quay.io](https://quay.io/repository/biocontainers/samtools?tag=latest&tab=tags)
3. Create the custom config accordingly:
   - For Docker:

     ```nextflow
     process {
         withName: SAMTOOLS_VIEW {
             container = 'quay.io/biocontainers/samtools:1.16.1--h6899075_1'
         }
     }
     ```

   - For Singularity:

     ```nextflow
     process {
         withName: SAMTOOLS_VIEW {
             container = 'https://depot.galaxyproject.org/singularity/samtools:1.16.1--h6899075_1'
         }
     }
     ```

   - For Conda:

     ```nextflow
     process {
         withName: SAMTOOLS_VIEW {
             conda = 'bioconda::samtools=1.16.1'
         }
     }
     ```

> **NB:** If you wish to periodically update individual tool-specific results (e.g. Samtools) generated by the pipeline then you must ensure to keep the `work/` directory otherwise the `-resume` ability of the pipeline will be compromised and it will restart from scratch.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

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

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
