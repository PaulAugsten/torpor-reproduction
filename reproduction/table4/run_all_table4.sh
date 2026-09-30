#!/bin/bash
# Table 4, all four columns: Native, GPU remoting, Swap-PCIe, Swap-NVLink.
# Usage: ./run_all_table4.sh   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs and results of the previous run.
set -u
cd "$(dirname "$0")"

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_native logs_remoting logs_swap_pcie logs_swap_nvlink
    rm -f results_*.txt
    rm -f log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log server_log*.txt tmp_output_*.txt
fi

STEPS=(run_table4_native.sh run_table4_remoting.sh run_table4_swap_pcie.sh run_table4_swap_nvlink.sh)
FAILED=()

for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash "$s" || FAILED+=("$s")
    echo
done

echo "===== Table 4: all columns ====="
for f in results_native.txt results_remoting.txt results_swap_pcie.txt results_swap_nvlink.txt; do
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
