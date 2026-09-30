#!/bin/bash
# Figure 10, all three bars at one function count: Native, Torpor, INFless-KA.
# Native runs first because it generates the trace the others replay.
# Usage: ./run_all_figure10.sh <FUNC_NUM>   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs of the previous run (sbatch_figure10.sh
# does this for every count after the first). Export SERVER_SIF to use a
# different server image for the Torpor bar.
set -u
cd "$(dirname "$0")"
FUNC_NUM=${1:?Usage: $0 <FUNC_NUM>}

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig10
    rm -f router.log server.log baseline.log ka.log router_stdout.log \
          log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
fi

STEPS=("./run_fig10_native.sh $FUNC_NUM" "./run_fig10_torpor.sh $FUNC_NUM" "./run_fig10_ka.sh $FUNC_NUM")
FAILED=()

for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash -c "$s" || FAILED+=("$s")
    echo
done

echo "===== Figure 10 (FUNC_NUM=$FUNC_NUM): all bars ====="
for f in logs_fig10/native_${FUNC_NUM}_result.txt logs_fig10/torpor_${FUNC_NUM}_result.txt logs_fig10/ka_${FUNC_NUM}_result.txt; do
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
