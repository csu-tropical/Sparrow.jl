#!/bin/bash
#===============================================================================
# Sparrow Slurm Batch Script
#
# Submit with: sbatch sparrow_slurm.sbatch
#
# This script launches a Sparrow workflow on a Slurm cluster.
# SlurmClusterManager reads SLURM_NTASKS from the environment to determine
# the number of Julia distributed workers. Each task gets its own process,
# and each process uses JULIA_NUM_THREADS threads.
#
# Customize the SBATCH directives and USER CONFIGURATION below for your system.
#===============================================================================

#--- SBATCH Directives --------------------------------------------------------
#SBATCH --job-name=sparrow
#SBATCH --output=sparrow_%j.out
#SBATCH --error=sparrow_%j.err
#SBATCH --ntasks=4                  # Number of distributed Julia workers
#SBATCH --cpus-per-task=4           # Threads per worker (maps to JULIA_NUM_THREADS)
#SBATCH --mem-per-cpu=4G            # Memory per CPU core
#SBATCH --time=04:00:00             # Wall clock limit (HH:MM:SS)
#SBATCH --partition=all             # Partition/queue name (change for your cluster)
##SBATCH --account=myaccount        # Uncomment and set your allocation/account
##SBATCH --mail-type=END,FAIL       # Uncomment for email notifications
##SBATCH --mail-user=user@example.edu

# Need to set this for some Slurm configurations to explicitly use PMI2 for worker communication
export SLURM_MPI_TYPE=pmi2

#--- USER CONFIGURATION -------------------------------------------------------
# Path to your Julia installation
JULIA_BIN="julia"

# Path to the Sparrow.jl project directory
SPARROW_PROJECT="${HOME}/Sparrow.jl"

# Workflow file to run (relative to SPARROW_PROJECT or absolute path)
WORKFLOW_FILE="workflows/my_workflow.jl"

# Processing datetime: "now" for realtime, or "YYYYmmdd", "YYYYmmdd_HH", "YYYYmmdd_HHMM"
DATETIME="now"

# Realtime mode: set to "--realtime" to enable, or leave empty for archive mode
REALTIME_FLAG=""

# Log file prefix (logs will be named <prefix>.log, <prefix>_worker_1.log, etc.)
LOG_PREFIX="sparrow_${SLURM_JOB_ID}"

# Verbosity level: 0=errors, 1=warnings, 2=info (default), 3=debug, 4=trace
VERBOSE=2

# Force reprocessing of already-processed files
FORCE_REPROCESS=""  # Set to "--force_reprocess" to enable

#--- ENVIRONMENT SETUP --------------------------------------------------------
# Set threads per worker from Slurm allocation
export JULIA_NUM_THREADS=${SLURM_CPUS_PER_TASK:-4}

# Ensure the project environment is active on all workers
export JULIA_PROJECT="${SPARROW_PROJECT}"

# Print job info for logging
echo "============================================="
echo "Sparrow Slurm Job: ${SLURM_JOB_ID}"
echo "Date: $(date)"
echo "Nodes: ${SLURM_JOB_NODELIST}"
echo "Tasks: ${SLURM_NTASKS}"
echo "CPUs/Task: ${SLURM_CPUS_PER_TASK}"
echo "Threads/Worker: ${JULIA_NUM_THREADS}"
echo "Workflow: ${WORKFLOW_FILE}"
echo "Datetime: ${DATETIME}"
echo "Project: ${SPARROW_PROJECT}"
echo "============================================="

#--- LAUNCH SPARROW ------------------------------------------------------------
${JULIA_BIN} --project="${SPARROW_PROJECT}" \
    --threads=${JULIA_NUM_THREADS} \
    -e '
    using Sparrow
    parsed_args = Sparrow.parse_arguments([
        ARGS[1],
        "--slurm",
        "--num_workers", ARGS[2],
        "--threads", ARGS[3],
        "--datetime", ARGS[4],
        "--log_prefix", ARGS[5],
        "--verbose", ARGS[6],
        ARGS[7:end]...
    ])
    Sparrow.main(parsed_args)
    ' \
    "${WORKFLOW_FILE}" \
    "${SLURM_NTASKS}" \
    "${JULIA_NUM_THREADS}" \
    "${DATETIME}" \
    "${LOG_PREFIX}" \
    "${VERBOSE}" \
    ${REALTIME_FLAG} \
    ${FORCE_REPROCESS}

EXIT_CODE=$?

echo "============================================="
echo "Sparrow job ${SLURM_JOB_ID} finished at $(date)"
echo "Exit code: ${EXIT_CODE}"
echo "============================================="

exit ${EXIT_CODE}
