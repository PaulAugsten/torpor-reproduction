#!/bin/bash
#SBATCH --job-name=figure11-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=24:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 11 run: five policy variants (Torpor, -FIFO, -Block, -LRU,
# -Random) on the mixed 8-model workload, 4 GPUs, 31-minute trace each.
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure11.sh           # 320 400 480 560
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure11.sh 480 560   # a subset
#
# Each variant takes about 50 minutes at 320 functions (client startup plus
# the 31-minute replay), so all four counts need roughly 18 hours. Splitting
# into two jobs ("320 400", "480 560") is safer. Run such jobs one after the
# other, never at the same time: they share this directory and kill stale
# processes by name.
#   JOB=$(sbatch --parsable sbatch_figure11.sh 320 400)
#   sbatch --dependency=afterany:$JOB sbatch_figure11.sh 480 560

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

source "$TORPOR/venv/bin/activate"

# Stage the model weights onto the node's tmpfs. Faster model loads make
# overlapping loads on one server, and the registration race they trigger,
# less likely (see README). Unset MODEL_CACHE_DIR to read from $TORPOR/models.
MODEL_SRC="$TORPOR/models"
export MODEL_CACHE_DIR=/dev/shm/models
rm -rf "$MODEL_CACHE_DIR"
mkdir -p "$MODEL_CACHE_DIR"
echo "Staging model weights to $MODEL_CACHE_DIR ..."
if ! cp -r "$MODEL_SRC/torch" "$MODEL_SRC/hf" "$MODEL_CACHE_DIR/"; then
    echo "ERROR: staging to $MODEL_CACHE_DIR failed -- aborting rather than"
    echo "       silently falling back to the shared filesystem."
    exit 1
fi
df -h /dev/shm | tail -1
du -sh "$MODEL_CACHE_DIR"
# Free the tmpfs however the job ends; it counts against the node's RAM.
trap 'rm -rf "$MODEL_CACHE_DIR"' EXIT

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_11"
mkdir -p "$RESULTS_DIR"

FUNC_NUMS=("$@")
[ "${#FUNC_NUMS[@]}" -eq 0 ] && FUNC_NUMS=(320 400 480 560)

# Wipe the previous run's logs once here; the per-count run_all calls keep
# them (log names contain the function count).
rm -rf logs_fig11
rm -f router.log server.log router_stdout.log \
      log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
export KEEP_LOGS=1

echo "=================================================="
echo "Figure 11 reproduction starting at $(date)"
echo "Function counts: ${FUNC_NUMS[*]}"
echo "=================================================="

FAILED_RUNS=()

for FUNC_NUM in "${FUNC_NUMS[@]}"; do
    echo "=================================================="
    echo "FUNC_NUM=$FUNC_NUM starting at $(date)"
    echo "=================================================="

    ./run_all_figure11.sh "$FUNC_NUM"
    RC=$?
    if [ "$RC" -ne 0 ]; then
        echo "WARNING: run_all_figure11.sh $FUNC_NUM exited with code $RC -- saving whatever results it produced and continuing"
        FAILED_RUNS+=("$FUNC_NUM")
    fi

    if compgen -G "logs_fig11/*_${FUNC_NUM}f_result.txt" > /dev/null; then
        cp logs_fig11/*_${FUNC_NUM}f_result.txt "$RESULTS_DIR/"
    else
        echo "WARNING: no result files found for FUNC_NUM=$FUNC_NUM"
    fi

    echo "FUNC_NUM=$FUNC_NUM done at $(date)"
    echo
done

echo "=================================================="
echo "Figure 11 done at $(date)"
if [ "${#FAILED_RUNS[@]}" -gt 0 ]; then
    echo "Function counts with at least one failed variant: ${FAILED_RUNS[*]}"
    echo "(check logs_batch/slurm-${SLURM_JOB_ID}.out for details, and $RESULTS_DIR for whichever result files did get saved)"
else
    echo "All runs completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_fig11/)"
