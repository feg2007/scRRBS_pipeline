#!/usr/bin/env bash

#SBATCH --job-name=rrbs_launcher      
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=youremail@example.com  # Replace with a valid email address or use an argument
#SBATCH --partition=all          
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4000M
#SBATCH --time=5-00:00:00
#SBATCH --output=slurm_outputs/%x_%j.out
#SBATCH --error=slurm_outputs/%x_%j.out

# Obtain positional arguments from command line
POSITIONAL=()
while [[ $# -gt 0 ]]
do
    
key="$1"
case $key in
    -f|--fastq)
    FASTQ="$2"
    shift # past argument
    shift # past value
    ;;
    -g|--genome)
    GENOME="$2"
    shift # past argument
    shift # past value
    ;;
    -r|--regions)
    REGIONS="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--pipeline)
    PIPELINE="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--target)
    RULE="$2"
    shift # past argument
    shift # past value
    ;;
    --qsub)
    QSUB=YES
    shift # past argument
    ;;
    -c|--cluster-config)
    CLUSTER_CONFIG="$2"
    shift # past argument
    shift # past value
    ;;
    --dag)
    DAG=YES
    shift # past argument
    ;;
    --dry-run)
    DRY_RUN=YES
    shift # past argument
    ;;
    *)
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done

set -- "${POSITIONAL[@]}" # restore positional parameters

# Get full paths
MY_GENOME=$(readlink -f ${GENOME})
MY_PATH=$(readlink -f ${FASTQ})
MY_PIPELINE=$(readlink -f ${PIPELINE})

# Echo variable paths to standard output
echo "Processing samples in ${MY_PATH}..."
echo "Using reference genome ${MY_GENOME}..."

if [ -n "${REGIONS}" ]
then
    MY_REGIONS=$(readlink -f ${REGIONS})
    echo "Using gene locations ${MY_REGIONS}..."
fi

echo "Using snakemake pipeline located at ${MY_PIPELINE} with target rule \"${RULE}\"..."

if [ -n "${CLUSTER_CONFIG}" ]
then
    MY_CLUSTER_CONFIG=$(readlink -f ${CLUSTER_CONFIG})
    echo "Submitting to cluster with configuration ${MY_CLUSTER_CONFIG}..."
fi

# Build config.yaml in same location as fastq files
cd $MY_PATH
echo "path: ${MY_PATH}" > config.yaml

barcodes=("ACAACC" "ACAGAC" "ACTCAC" "AGAAGG" "AGGATG" "ATCAAG" "ATCGAC" "CAAGAG" "CATGAC" "CCATAG" "CCTTCG" "CGGTAG" "CTATTG" "CTCAGC" "GAAGTC" "GCATTC" "GGTAAC" "GTGAGG" "GTTGAG" "TATCTC" "TCTCTG" "TGACAG" "TGCTGC" "TGTAGG")

echo "barcodes:" >> config.yaml

for barcode in ${barcodes[@]}; do
    echo "- ${barcode}" >> config.yaml
done

echo "genome: ${MY_GENOME}" >> config.yaml
if [ -n "${REGIONS}" ]                                                                                                                                                              
then 
    echo "regions: ${MY_REGIONS}" >> config.yaml
fi
echo "scripts: ${MY_PIPELINE}" >> config.yaml

MY_SNAKEMAKE=$(which snakemake)

# Build directed acyclic graph if requested
if [ -n "${DAG}" ]
then
    $MY_SNAKEMAKE -np -s ${MY_PIPELINE}/ProcessRRBS.mk --configfile ${MY_PATH}/config.yaml --dag ${RULE} | dot -Tsvg > ${MY_PATH}/dag.svg
fi

# Execute snakemake pipeline for processing RRBS data if not dry run
if [ -z "${DRY_RUN}" ]
then
    if [ -n "${QSUB}" ]
    then
	$MY_SNAKEMAKE -s ${MY_PIPELINE}/ProcessRRBS.mk \
                --configfile ${MY_PATH}/config.yaml \
                --jobs 5 \
                --nolock \
                --rerun-incomplete \
                --latency-wait 60 \
                --cluster-config ${MY_CLUSTER_CONFIG} \
		        --cluster "sbatch -J {cluster.job-name} -p {cluster.partition} -t {cluster.time} -c {cluster.cpus-per-task} --mem={cluster.mem} -o {cluster.output} -e {cluster.error} --mail-type={cluster.mail-type} --mail-user={cluster.mail-user}" \
                ${RULE}
    else
	$MY_SNAKEMAKE -s ${MY_PIPELINE}/ProcessRRBS.mk \
                --configfile ${MY_PATH}/config.yaml \
                --nolock \
                --rerun-incomplete \
                --latency-wait 60 \
                ${RULE}
    fi
fi

echo "Done."

