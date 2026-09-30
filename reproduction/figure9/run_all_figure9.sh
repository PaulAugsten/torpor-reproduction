#!/bin/bash
# Figure 9, all runs: Native and Torpor over four random traces (upstream
# labels -5, -7, -1, -10). Native runs first, as in the upstream README. Each
# trace is generated once and cached in ../../tools, so Torpor replays exactly
# the same requests. Both systems run in one job because Torpor's per-request
# cost varies between jobs.
# Usage: ./run_all_figure9.sh   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs of the previous run. Export SERVER_SIF to
# use a different server image for the Torpor runs.
set -u
cd "$(dirname "$0")"

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig9
    rm -f router.log server.log baseline.log router_stdout.log \
          log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
fi

TRACE_IDS=(-5 -7 -1 -10)

STEPS=()
for t in "${TRACE_IDS[@]}"; do
    STEPS+=("./run_fig9_native.sh $t")
done
for t in "${TRACE_IDS[@]}"; do
    STEPS+=("./run_fig9_torpor.sh $t")
done

FAILED=()
for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash -c "$s" || FAILED+=("$s")
    echo
done

echo "===== Figure 9: all runs ====="
for v in native torpor; do
    for t in "${TRACE_IDS[@]}"; do
        f="logs_fig9/${v}_trace${t}_result.txt"
        [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
    done
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
