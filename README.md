# logan_blaster: Blast a query against Logan data

Align genomic sequences with [Logan](https://github.com/IndexThePlanet/Logan/) contigs.

## Two main modes
1. From a query and a list of Logan accessions.  
2. From a [Logan-Search](https://logan-search.org/) session id. The query and Logan accessions are then automaticaly retreived.

In any case, for each accession, `logan_blaster` 
1. Dowloads the Logan contigs,
2. Recruits contigs that contain at least one shared k-mer (k=17 by default) with the query (uses `[back_to_sequences](https://github.com/pierrepeterlongo/back_to_sequences)`), 
3. Runs a local blast between the query and this subset of contigs.


## Requires 
- blast: *on mac* `brew install blast` or look at [blast installation web page](https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/)
- back_to_sequences: see back_to_sequences installation [web page](https://b2s-doc.readthedocs.io/en/latest/usage.html#installation])
- jq: see [jq installation web page](https://jqlang.org/)

## Running the `logan_blaster.sh` script

```bash
./logan_blaster.sh
  Usage: ./logan_blaster.sh --session <logan seesion ID> or (--query <query_file.fa> --accessions <accessions.txt>) [--delete] [--kmer-size <k>] [--limit <n>]
  Options:
  Input choice1: session ID
    -s, --session     Logan session ID, eg. kmviz-b2bce461-ca13-4a45-b0b4-6c894eacf103
  Input choice2: accessions and query files
    -a, --accessions  Path to accessions.txt file. Containing one accession per line)
    -q, --query       Path to query fasta file
  Global options:
    -u, --unitigs     Consider the unitigs verison of the accessions instead of contigs
    -k, --kmer-size K-mer size for sequence recruitment with back_to_sequences (default: 17)
    -l, --limit     Limit number of accessions to process from accession file (default: no limit)
    -d, --delete    Delete recruited accessions and accessions files after processing (default: keep all files)
    -h, --help      Show this help message
```

## Example running from session.
```bash
./logan_blaster.sh -s kmviz-b2bce461-ca13-4a45-b0b4-6c894eacf103
```

## Example running from accessions and query files.
This usage enables to select specific accessions to process, also ordering them, and to provide any custom query file.

```bash
./logan_blaster.sh  -a example/accessions.txt -q example/query.fa
```

## Authors
- [Pierre Peterlongo](https://people.rennes.inria.fr/Pierre.Peterlongo/)
- [Téo Lemane](https://tlemane.github.io/)
