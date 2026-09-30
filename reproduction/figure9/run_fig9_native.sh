#!/bin/bash
# Figure 9, Native run for one random trace.
# Usage: ./run_fig9_native.sh <TRACE_ID>   (upstream labels: -5 -7 -1 -10)
# A negative rate makes sender_fix_rate.py draw random per-function rates
# (Azure invocation pattern x10) and cache the trace as
# ../../tools/req_arrivals_40_5_<TRACE_ID>.npy for the Torpor run.
# pipefail so that a crashing analyzer is not hidden behind tee.
set -u -o pipefail
cd "$(dirname "$0")"
source ../common/env.sh
TRACE_ID=${1:?Usage: $0 <TRACE_ID (e.g. -5)>}
FUNC_NUM=40
MINUTES=5
mkdir -p logs_fig9
source ../common/kill_stale.sh
source ../common/ports.sh

cleanup() {
    echo "[cleanup] stopping native processes..."
    kill_stale_processes
    rm -rf /dev/shm/ipc
    [ -f router.log ]   && cp router.log   "logs_fig9/native_trace${TRACE_ID}.log"
    [ -f baseline.log ] && cp baseline.log "logs_fig9/native_trace${TRACE_ID}_baseline.log"
    PROC_DIR="logs_fig9/native_trace${TRACE_ID}_proc"
    for f in log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log; do
        [ -e "$f" ] || continue
        mkdir -p "$PROC_DIR" && mv "$f" "$PROC_DIR/"
    done
}
trap cleanup EXIT

kill_stale_processes
rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc

rm -f router.log baseline.log
rm -f "logs_fig9/native_trace${TRACE_ID}_result.txt"
rm -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log

# 1. Native router: 40 resnet152 functions spread across all 4 GPUs
nohup taskset -c 200 python3 baseline_native.py -m resnet152 -s 4 -f "$FUNC_NUM" > baseline.log 2>&1 &
sleep 5

# 2. Wait for endpoints
echo "Waiting for $FUNC_NUM native endpoints..."
for ((i=0; i<FUNC_NUM; i++)); do
    PORT=$((CLIENT_PORT_BASE + i))
    COUNT=0
    until curl -s "http://localhost:$PORT" > /dev/null; do
        sleep 1
        COUNT=$((COUNT + 1))
        if [ $COUNT -ge 60 ]; then
            echo "Warning: endpoint $PORT not ready after 60s, skipping..."
            break
        fi
    done
done
echo "Endpoints up (or timed out). Settling..."
sleep 5

# 3. Send the random-rate trace (generated on first use, then cached)
python3 sender_fix_rate.py "$FUNC_NUM" "$MINUTES" 0 "$TRACE_ID" || { echo "sender failed"; exit 1; }
sleep 10

# 4. Analyze: per-GPU normalized load and P98 latency (cleanup runs via trap)
python3 figure9_analyze_router_log.py router.log \
    | tee "logs_fig9/native_trace${TRACE_ID}_result.txt"
