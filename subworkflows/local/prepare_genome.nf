//
// Uncompress and prepare reference genome files
//

include { GUNZIP        } from '../../modules/nf-core/gunzip/main'
include { UNMASK        } from '../../modules/local/unmask'
include { UNTAR         } from '../../modules/nf-core/untar/main'
include { BWAMEM2_INDEX } from '../../modules/nf-core/bwamem2/index/main'


workflow PREPARE_GENOME {
    take:
    fasta    // channel: [ meta, /path/to/fasta ]


    main:
    ch_versions = Channel.empty()


    // Uncompress genome fasta file if required
    if ( params.fasta.endsWith('.gz') ) {
        ch_unzipped = GUNZIP ( fasta ).gunzip
        ch_versions = ch_versions.mix ( GUNZIP.out.versions )
    } else {
        ch_unzipped = fasta
    }

    ch_unzipped
    | map { meta, fa -> [ meta + [id: fa.baseName, genome_size: fa.size()], fa] }
    | set { ch_fasta }

    // Unmask genome fasta
    UNMASK ( ch_fasta )
    ch_versions = ch_versions.mix ( UNMASK.out.versions.first() )


    // Generate BWA index
    if ( params.bwamem2_index ) {
        Channel.fromPath ( params.bwamem2_index )
        | combine ( ch_fasta )
        | map { bwa, meta, fa -> [ meta, bwa ] }
        | set { ch_bwamem }

        if ( params.bwamem2_index.endsWith('.tar.gz') ) {
            ch_bwamem2_index = UNTAR ( ch_bwamem ).untar
            ch_versions      = ch_versions.mix ( UNTAR.out.versions.first() )
        } else {
            ch_bwamem2_index = ch_bwamem
        }

    } else {
        ch_bwamem2_index = BWAMEM2_INDEX ( UNMASK.out.fasta ).index
        ch_versions      = ch_versions.mix ( BWAMEM2_INDEX.out.versions.first() )
    }


    emit:
    fasta    = UNMASK.out.fasta.first()    // channel: [ meta, /path/to/fasta ]
    bwaidx   = ch_bwamem2_index.first()    // channel: [ meta, /path/to/bwamem2/index_dir/ ]
    versions = ch_versions                 // channel: [ versions.yml ]
}
