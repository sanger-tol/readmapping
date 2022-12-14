//
// This file holds several functions specific to the workflow/readmapping.nf in the sanger-tol/readmapping pipeline
//

class WorkflowReadmapping {

    //
    // Check and validate parameters
    //
    public static void initialise(params, log) {

        if (!params.fasta) {
            log.error "Genome fasta file not specified with e.g. '--fasta genome.fa' or via a detectable config file."
            System.exit(1)
        }

    }

}
