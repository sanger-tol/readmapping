//
// Uncompress and prepare reference genome files
//
include { GUNZIP        } from '../../modules/nf-core/gunzip/main'
include { UNTAR         } from '../../modules/nf-core/untar/main'

include { MASK_UNMASK   } from '../../modules/sanger-tol/mask/unmask/main'

workflow PREPARE_GENOME {
    take:
    fasta    // channel: [ meta, /path/to/fasta ]

    main:
    // Uncompress genome fasta file if required
    if ( params.fasta.endsWith('.gz') ) {
        ch_unzipped = GUNZIP ( fasta ).gunzip
    } else {
        ch_unzipped = fasta
    }

    ch_fasta = ch_unzipped
    .map { meta, fa -> [ meta + [id: fa.baseName, genome_size: fa.size()], fa] }

    // MASK_UNMASK genome fasta
    MASK_UNMASK ( ch_fasta )

    emit:
    fasta    = MASK_UNMASK.out.unmasked.first()    // channel: [ meta, /path/to/fasta ]
}
