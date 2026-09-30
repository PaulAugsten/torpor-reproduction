#!/bin/bash
# Figure 11, every variant at one function count: Torpor, -FIFO, -Block, -LRU,
# and -Random (320 and 400 only, as in upstream's Figure11_README.md).
# Usage: ./run_all_figure11.sh <FUNC_NUM>   (compute node, venv active)
# FUNC_NUM in the paper: 320, 400, 480, 560.
# Set KEEP_LOGS=1 to keep the logs of the previous run. Export SERVER_SIF to
# use a different server image.
set -u
cd "$(dirname "$0")"
FUNC_NUM=${1:?Usage: $0 <FUNC_NUM>}

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig11
    rm -f router.log server.log router_stdout.log \
          log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
fi

# Upstream runs Torpor-Random at 320 and 400 only. RANDOM_MAX_FUNC overrides.
VARIANTS=(torpor fifo block lru)
if [ "$FUNC_NUM" -le "${RANDOM_MAX_FUNC:-400}" ]; then
    VARIANTS+=(random)
else
    echo "Skipping the random variant at FUNC_NUM=$FUNC_NUM (upstream collects it at 320/400 only)."
fi

FAILED=()
for v in "${VARIANTS[@]}"; do
    echo "###### ./run_fig11_variant.sh $v $FUNC_NUM ######"
    ./run_fig11_variant.sh "$v" "$FUNC_NUM" || FAILED+=("$v")
    echo
done

echo "===== Figure 11 (FUNC_NUM=$FUNC_NUM): all variants ====="
for v in "${VARIANTS[@]}"; do
    f="logs_fig11/${v}_${FUNC_NUM}f_result.txt"
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED variants: ${FAILED[*]}"
    exit 1
fi
