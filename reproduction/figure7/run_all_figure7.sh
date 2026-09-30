#!/bin/bash
# Figure 7, all four variants: Baseline, +Group, +Pipeline, +Pinned.
# The order does not matter; every model gets a fresh server.
# Usage: ./run_all_figure7.sh   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs and results of the previous run.
set -u
cd "$(dirname "$0")"

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig7_baseline logs_fig7_group logs_fig7_pinned logs_fig7_pipeline
    rm -f results_*.txt
    rm -f log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log server_log*.txt tmp_output_*.txt
fi

STEPS=(run_fig7_baseline.sh run_fig7_group.sh run_fig7_pinned.sh run_fig7_pipeline.sh)
FAILED=()

for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash "$s" || FAILED+=("$s")
    echo
done

echo "===== Figure 7: all variants ====="
for f in results_fig7_baseline.txt results_fig7_group.txt results_fig7_pinned.txt results_fig7_pipeline.txt; do
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
