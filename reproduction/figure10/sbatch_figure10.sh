#!/bin/bash
#SBATCH --job-name=figure10-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=10:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 10 run (Native, Torpor, INFless-KA) at 40, 80, 120, 160 functions.
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure10.sh

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

source "$TORPOR/venv/bin/activate"

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_10"
mkdir -p "$RESULTS_DIR"

# Wipe the previous run's logs once here; the per-count run_all calls keep
# them (log names contain the function count).
rm -rf logs_fig10
rm -f router.log server.log baseline.log ka.log router_stdout.log \
      log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
export KEEP_LOGS=1

FAILED_RUNS=()

for FUNC_NUM in 40 80 120 160; do
    echo "=================================================="
    echo "FUNC_NUM=$FUNC_NUM starting at $(date)"
    echo "=================================================="

    ./run_all_figure10.sh "$FUNC_NUM"
    RC=$?
    if [ "$RC" -ne 0 ]; then
        echo "WARNING: run_all_figure10.sh $FUNC_NUM exited with code $RC -- saving whatever results it produced and continuing"
        FAILED_RUNS+=("$FUNC_NUM")
    fi

    if compgen -G "logs_fig10/*_${FUNC_NUM}_result.txt" > /dev/null; then
        cp logs_fig10/*_${FUNC_NUM}_result.txt "$RESULTS_DIR/"
    else
        echo "WARNING: no result files found for FUNC_NUM=$FUNC_NUM"
    fi

    echo "FUNC_NUM=$FUNC_NUM done at $(date)"
    echo
done

echo "=================================================="
echo "All FUNC_NUM values processed."
if [ "${#FAILED_RUNS[@]}" -gt 0 ]; then
    echo "FUNC_NUM values with at least one failed step: ${FAILED_RUNS[*]}"
    echo "(check logs_batch/slurm-${SLURM_JOB_ID}.out for details, and $RESULTS_DIR for whichever result files did get saved)"
else
    echo "All runs completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_fig10/)"
