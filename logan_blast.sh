#!/bin/bash

SESSION_ID=""
ACCESSION_FILE=""
QUERY_FILE=""
DELETE=false
UNITIGS=false
LIMIT=0
KMER_SIZE=17

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;034m'
NOCOLOR='\033[0m'

print_help() {
    echo -e "Usage: $0 --session <logan seesion ID> or (--query <query_file.fa> --accessions <accessions.txt>) [--delete] [--kmer-size <k>] [--limit <n>]"
    echo -e "Options:"
    echo -e " Input choice1: session ID"
    echo -e "  -s, --session     Logan session ID, eg. kmviz-b2bce461-ca13-4a45-b0b4-6c894eacf103"
    echo -e " Input choice2: accessions and query files"
    echo -e "  -a, --accessions  Path to accessions.txt file. Containing one accession per line)"
    echo -e "  -q, --query       Path to query fasta file"
    echo -e " Global options:"
    echo -e "  -u, --unitigs     Consider the unitigs verison of the accessions instead of contigs"
    echo -e "  -k, --kmer-size K-mer size for sequence recruitment with back_to_sequences (default: ${KMER_SIZE})"
    echo -e "  -l, --limit     Limit number of accessions to process from accession file (default: no limit)"
    echo -e "  -d, --delete    Delete recruited accessions and accessions files after processing (default: keep all files)"
    echo -e "  -h, --help      Show this help message"
}

run_blast() {
    set -euo pipefail

    local QUERY_FASTA="$1"
    local TARGET_FASTA="$2"



    local QUERY_BASENAME
    local TARGET_BASENAME
    QUERY_BASENAME=$(basename "${QUERY_FASTA%.*}")
    TARGET_BASENAME=$(basename "${TARGET_FASTA%.*}")
    local OUTPUT_DIR="${QUERY_BASENAME}_vs_${TARGET_BASENAME}"

    mkdir -p "$OUTPUT_DIR"

    echo -e "[INFO] Creating BLAST database from ${TARGET_FASTA}..."
    makeblastdb -dbtype nucl -in "$TARGET_FASTA" -out "${OUTPUT_DIR}/targets_db" >/dev/null 2>&1

    local QUERY_ID
    QUERY_ID=$(grep -m1 '^>' "$QUERY_FASTA" | sed 's/^>//;s/ .*//')

    echo -e "[INFO] Running BLAST for each target sequence..."

    grep '^>' "$TARGET_FASTA" | sed 's/^>//;s/ .*//' | while read -r TARGET_ID; do
        [[ -z "$TARGET_ID" ]] && continue
        local OUTPUT_FILE="${OUTPUT_DIR}/${QUERY_ID}_vs_${TARGET_ID}.txt"

        echo -e "  - Aligning ${QUERY_ID} vs ${TARGET_ID}..."
        blastn \
            -query "$QUERY_FASTA" \
            -db "${OUTPUT_DIR}/targets_db" \
            -out "$OUTPUT_FILE" \
            -outfmt 0 \
            -num_alignments 1 \
            -sorthits 0 >/dev/null 2>&1
    done

    echo -e "\033[92m[INFO] Results are in directory ${OUTPUT_DIR}${NOCOLOR}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--session)
            SESSION_ID="$2"
            shift 2
            ;;
        -a|--accessions)
            ACCESSION_FILE="$2"
            shift 2
            ;;
        -q|--query)
            QUERY_FILE="$2"
            shift 2
            ;;
        -k|--kmer-size)
            KMER_SIZE="$2"
            shift 2
            ;;
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -d|--delete)
            DELETE=true
            shift
            ;;
        -u|--unitigs)
            UNITIGS=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NOCOLOR}"
            print_help
            exit 1
            ;;
    esac
done

# If session option was provided, do not allow accessions or query options
if [[ -n "$SESSION_ID" && ( -n "$ACCESSION_FILE" || -n "$QUERY_FILE" ) ]]; then
    echo -e "${RED}Error: --session (-s) cannot be combined with --accessions (-a) or --query (-q).${NOCOLOR}"
    print_help
    exit 1
fi

if [[ -n "$SESSION_ID" ]]; then
    ACCESSION_FILE="accessions_${SESSION_ID}.txt"
    if [ ! -f "$ACCESSION_FILE" ]; then
        wget https://logan-search.org/api/download/${SESSION_ID} -O ${SESSION_ID}.zip

        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to download https://logan-search.org/api/download/${SESSION_ID}.${NOCOLOR}"
            echo -e "${RED}Check your internet connexion. ${NOCOLOR}"
            exit 1
        fi
        unzip ${SESSION_ID}.zip session.json
        mv session.json ${SESSION_ID}.json
        jq -r '.. | ._metadata?.ID? // empty | .[]' ${SESSION_ID}.json > ${SESSION_ID}_acc.txt
        ACCESSION_FILE="${SESSION_ID}_acc.txt"
        QUERY_FILE="${SESSION_ID}_query.fa"
        echo -n ">" > ${QUERY_FILE}
        jq -r '.. | ._query?._name? // empty' ${SESSION_ID}.json >> ${QUERY_FILE}
        jq -r '.. | ._query?._seq? // empty' ${SESSION_ID}.json >> ${QUERY_FILE}
    fi
fi

if [[ -z "$ACCESSION_FILE" || -z "$QUERY_FILE" ]]; then
    echo -e "${RED}Error: --accessions and --query are required.${NOCOLOR}"
    print_help
    exit 1
fi

if [ ! -f "$QUERY_FILE" ]; then
    echo -e "${RED}Error: Query file '$QUERY_FILE' does not exist.${NOCOLOR}"
    exit 1
fi

if [ ! -f "$ACCESSION_FILE" ]; then
    echo -e "${RED}Error: Accessions file '$ACCESSION_FILE' does not exist.${NOCOLOR}"
    exit 1
fi

if ! [[ "$KMER_SIZE" =~ ^[0-9]+$ ]] || [ "$KMER_SIZE" -le 0 ]; then
    echo -e "${RED}Error: K-mer size must be a positive integer.${NOCOLOR}"
    exit 1
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -lt 0 ]; then
    echo -e "${RED}Error: Limit must be a non-negative integer.${NOCOLOR}"
    exit 1
fi

## check that back_to_sequences is installed
if ! command -v back_to_sequences &> /dev/null; then
    echo -e "${RED}Error: back_to_sequences could not be found. Please install it first https://github.com/pierrepeterlongo/back_to_sequences.${NOCOLOR}"
    exit 1
fi

if ! command -v makeblastdb >/dev/null 2>&1 || ! command -v blastn >/dev/null 2>&1; then
    echo -e "${RED}Error: BLAST+ executables 'makeblastdb' and/or 'blastn' not found in PATH.${NOCOLOR}"
    return 1
fi

# check that jq is installed
if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Error: 'jq' could not be found. Please install jq (https://jqlang.org/) and ensure it's in your PATH.${NOCOLOR}"
    exit 1
fi

type=contig
if [ "$UNITIGS" = true ]; then
    type=unitig
fi


# QUERY_FILE base name without extension
# Remove all extensions from QUERY_FILE to get the base name
QUERY_BASENAME=$(basename "$QUERY_FILE")
QUERY_BASENAME="${QUERY_BASENAME%%.*}"

counter=0
while read accession; do
    if [ "$LIMIT" -ne 0 ] && [ "$counter" -ge "$LIMIT" ]; then
        echo -e "\n${YELLOW}Reached limit of $LIMIT accessions. Stopping further processing.${NOCOLOR}"
        break
    fi
    counter=$((counter + 1))
    echo -e "\n\033[1;34m========================================${NOCOLOR}"
    echo -e "\033[1;36m>>> Processing accession: ${accession} <<<${NOCOLOR}"
    echo -e "\033[1;34m========================================${NOCOLOR}"
	if [ ! -f "${accession}.${type}s.fa.zst" ]; then
		echo -e "${YELLOW}Downloading ${accession}.${type}s.fa.zst...${NOCOLOR}"
        if [ "$UNITIGS" = false ]; then
            wget https://s3.amazonaws.com/logan-pub/c/${accession}/${accession}.contigs.fa.zst 
            else 
            wget https://s3.amazonaws.com/logan-pub/u/${accession}/${accession}.unitigs.fa.zst
        fi

        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to download ${accession}.${type}s.fa.zst from S3. Skipping this accession.${NOCOLOR}"
            if [ "$UNITIGS" = false ]; then
                echo -e "${RED}This usually occurs because some logan accessions do not have contigs files (they have only unitigs files).${NOCOLOR}"
            fi
            continue
        fi
	else
		echo -e "${YELLOW}Using existing local version of ${accession}.${type}s.fa.zst...${NOCOLOR}"
	fi
	echo -e "${YELLOW}Recruiting sequences from ${accession}.${type}s.fa.zst with a match with ${QUERY_FILE}...${NOCOLOR}"
	echo -e "${GREEN}back_to_sequences --kmer-size ${KMER_SIZE} --in-kmers ${QUERY_FILE} --in-sequences ${accession}.${type}s.fa.zst --out-sequences T.fa${NOCOLOR}"
	back_to_sequences --kmer-size ${KMER_SIZE} --in-kmers ${QUERY_FILE} --in-sequences  ${accession}.${type}s.fa.zst --out-sequences ${accession}.recruited_${type}s.fa > /dev/null 2>&1

    ## check if any sequences were recruited
    if [ ! -s "${accession}.recruited_${type}s.fa" ]; then
        echo -e "${YELLOW}\tNo sequences were recruited from ${accession}.${type}s.fa.zst. Skipping BLAST step.${NOCOLOR}"
        if [ "$DELETE" = true ]; then
            echo -e "${YELLOW}Deleting ${accession}.recruited_${type}s.fa and ${accession}.${type}s.fa.zst...${NOCOLOR}"
            rm -f ${accession}.recruited_${type}s.fa
            rm -f ${accession}.${type}s.fa.zst
        fi
        continue
    fi

	echo -e "${YELLOW}Aligning recruited sequences from ${accession}.${type}s.fa.zst with ${QUERY_FILE}...${NOCOLOR}"
    run_blast "$QUERY_FILE" "${accession}.recruited_${type}s.fa"
    if [ "$DELETE" = true ]; then
        echo -e "${YELLOW}Deleting ${accession}.recruited_${type}s.fa and ${accession}.${type}s.fa.zst...${NOCOLOR}"
        rm -f ${accession}.recruited_${type}s.fa
        rm -f ${accession}.${type}s.fa.zst
    fi
    # Clean the blast db files
    rm -f ${accession}.recruited_${type}s_vs_${QUERY_BASENAME}/targets_db*
done < ${ACCESSION_FILE}

echo

    echo -e "\n${BLUE}================"
    echo -e "${BLUE}>>> All done <<<"
    echo -e "${BLUE}================\n"
# if --delete was not used, show user how to remove all intermediate files
if [ "$DELETE" = false ]; then
    echo -e "${YELLOW}You  did not use --delete option. So you can manually remove all intermediate files (recruited ${type}s and ${type}s files) by running:${NOCOLOR}"
    echo -e "${GREEN}rm -f *.recruited_${type}s.fa *.${type}s.fa.zst${NOCOLOR}"
fi

echo
echo -e "${YELLOW}Results can be found in directories <accessions>.recruited_${type}s_vs_${QUERY_BASENAME} for each accession id in the ${ACCESSION_FILE}.${NOCOLOR}"