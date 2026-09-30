#!/bin/bash
# Figure 6, both bars: Torpor and Torpor w/o batch.
# Usage: ./run_all_figure6.sh   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs and results of the previous run.
set -u
cd "$(dirname "$0")"

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig6_torpor logs_fig6_nobatch
    rm -f results_*.txt
    rm -f log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log server_log*.txt tmp_output_*.txt
    rm -f fig6_nobatch/log_client_*.txt
fi

STEPS=(run_fig6_torpor.sh run_fig6_nobatch.sh)
FAILED=()

for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash "$s" || FAILED+=("$s")
    echo
done

echo "===== Figure 6: all bars ====="
for f in results_fig6_torpor.txt results_fig6_nobatch.txt; do
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
