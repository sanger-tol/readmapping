#!/usr/bin/env python

# This script is based on the example at: https://raw.githubusercontent.com/nf-core/test-datasets/viralrecon/samplesheet/samplesheet_test_illumina_amplicon.csv

import os
import sys
import errno
import argparse


def parse_args(args=None):
    Description = "Reformat nf-core/readmapping samplesheet file and check its contents."
    Epilog = "Example usage: python check_samplesheet.py <FILE_IN> <FILE_OUT>"

    parser = argparse.ArgumentParser(description=Description, epilog=Epilog)
    parser.add_argument("FILE_IN", help="Input samplesheet file.")
    parser.add_argument("FILE_OUT", help="Output file.")
    return parser.parse_args(args)


def make_dir(path):
    if len(path) > 0:
        try:
            os.makedirs(path)
        except OSError as exception:
            if exception.errno != errno.EEXIST:
                raise exception


def print_error(error, context="Line", context_str=""):
    error_str = "ERROR: Please check samplesheet -> {}".format(error)
    if context != "" and context_str != "":
        error_str = "ERROR: Please check samplesheet -> {}\n{}: '{}'".format(
            error, context.strip(), context_str.strip()
        )
    print(error_str)
    sys.exit(1)


def check_samplesheet(file_in, file_out):
    """
    This function checks that the samplesheet follows the following structure:

    sample,datatype,datafile,library
    sample1,hic,/path/to/file1.cram,ID1
    sample1,illumina,/path/to/file2.cram,ID2
    sample1,pacbio,/path/to/file1.bam,ID3
    sample1,ont,/path/to/file.fq.gz,ID4

    For an example see:
    https://raw.githubusercontent.com/nf-core/test-datasets/viralrecon/samplesheet/samplesheet_test_illumina_amplicon.csv
    """

    sample_mapping_dict = {}
    with open(file_in, "r") as fin:

        ##* Check header
        MIN_COLS = 3
        HEADER = ["sample", "datatype", "datafile", "library"]
        header = [x.strip('"') for x in fin.readline().strip().split(",")]
        if header[: len(HEADER)] != HEADER:
            print("ERROR: Please check samplesheet header -> {} != {}".format(",".join(header), ",".join(HEADER)))
            sys.exit(1)

        ## Check sample entries
        for line in fin:
            lspl = [x.strip().strip('"') for x in line.strip().split(",")]

            # Check valid number of columns per row
            if len(lspl) < len(HEADER):
                print_error(
                    "Invalid number of columns (minimum = {})!".format(len(HEADER)),
                    "Line",
                    line,
                )
            num_cols = len([x for x in lspl if x])
            if num_cols < MIN_COLS:
                print_error(
                    "Invalid number of populated columns (minimum = {})!".format(MIN_COLS),
                    "Line",
                    line,
                )

            ##* Check sample name entries
            sample, datatype, datafile, library = lspl[: len(HEADER)]
            sample = sample.replace(" ", "_")
            if not sample:
                print_error("Sample entry has not been specified!", "Line", line)

            ##* Check datatype name entries
            datatypes = ["hic", "pacbio", "illumina", "ont", "pacbio_clr"]
            if datatype:
                if datatype not in datatypes:
                    print_error(
                        "Data type must be one of {}.".format(",".join(datatypes)),
                        "Line",
                        line,
                    )
            else:
                print_error(
                    "Data type has not been specified!. Must be one of {}.".format(",".join(datatypes)),
                    "Line",
                    line,
                )

            ##* Check data file extension
            if datafile:
                if datafile.find(" ") != -1:
                    print_error(
                        "Data file contains spaces!",
                        "Line",
                        line,
                    )
                if not datafile.endswith(".cram") and not datafile.endswith(".bam") and not datafile.endswith(".fq.gz") and not datafile.endswith(".fastq.gz"):
                    print_error(
                        "Data file does not have extension '.cram' or '.bam' or compressed '.f*q'!",
                        "Line",
                        line,
                    )

            ##* Create sample mapping dictionary = { sample: [ datatype, datafile, library ] }
            sample_info = [datatype, datafile, library]
            if sample not in sample_mapping_dict:
                sample_mapping_dict[sample] = [sample_info]
            else:
                if sample_info in sample_mapping_dict[sample]:
                    print_error("Samplesheet contains duplicate rows!", "Line", line)
                else:
                    sample_mapping_dict[sample].append(sample_info)

    ##* Write validated samplesheet with appropriate columns
    if len(sample_mapping_dict) > 0:
        out_dir = os.path.dirname(file_out)
        make_dir(out_dir)
        with open(file_out, "w") as fout:
            fout.write(",".join(["sample", "datatype", "datafile", "library"]) + "\n")
            for sample in sorted(sample_mapping_dict.keys()):

                for idx, val in enumerate(sample_mapping_dict[sample]):
                    fout.write(",".join(["{}_T{}".format(sample, idx + 1)] + val) + "\n")
    else:
        print_error("No entries to process!", "Samplesheet: {}".format(file_in))


def main(args=None):
    args = parse_args(args)
    check_samplesheet(args.FILE_IN, args.FILE_OUT)


if __name__ == "__main__":
    sys.exit(main())
