#!/bin/bash
# Figure 10, Native bar. Usage: ./run_fig10_native.sh <FUNC_NUM>
# pipefail so that a crashing analyzer is not hidden behind tee.
set -u -o pipefail
cd "$(dirname "$0")"
source ../common/env.sh
FUNC_NUM=${1:?Usage: $0 <FUNC_NUM>}
MINUTES=5
mkdir -p logs_fig10
source ../common/kill_stale.sh
source ../common/ports.sh

cleanup() {
    echo "[cleanup] stopping native processes..."
    kill_stale_processes
    rm -rf /dev/shm/ipc
    [ -f router.log ]   && cp router.log   "logs_fig10/native_${FUNC_NUM}_${MINUTES}min.log"
    [ -f baseline.log ] && cp baseline.log "logs_fig10/native_${FUNC_NUM}_${MINUTES}min_baseline.log"
    PROC_DIR="logs_fig10/native_${FUNC_NUM}_${MINUTES}min_proc"
    for f in log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log; do
        [ -e "$f" ] || continue
        mkdir -p "$PROC_DIR" && mv "$f" "$PROC_DIR/"
    done
}
trap cleanup EXIT

kill_stale_processes
rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc

# Remove the previous run's logs first: if the driver dies at startup, the
# analyzer would otherwise report the previous run's results as this one's.
rm -f router.log baseline.log
rm -f "logs_fig10/native_${FUNC_NUM}_result.txt"
rm -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log

# 1. Native router: one GPU-resident endpoint per function, at most 72
# (MAX_CONTAINERS in baseline_native.py, set by upstream).
# Pinned to a core outside all NUMA_CORES ranges so the clients cannot starve it.
nohup taskset -c 200 python3 baseline_native.py -m resnet152 -s 4 -f "$FUNC_NUM" > baseline.log 2>&1 &
sleep 5

# 2. Wait for endpoints
if [ "$FUNC_NUM" -gt 72 ]; then CHECK_LIMIT=72; else CHECK_LIMIT=$FUNC_NUM; fi
echo "Waiting for $CHECK_LIMIT native endpoints..."
for ((i=0; i<CHECK_LIMIT; i++)); do
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

# 3. Replay the trace (generates tools/req_arrivals_${FUNC_NUM}_${MINUTES}min_trace.npy on first use)
python3 sender_from_trace.py "$FUNC_NUM" "$MINUTES" 0 || { echo "sender failed"; exit 1; }
sleep 10

# 4. Analyze (cleanup runs afterwards via trap)
python3 figure10_analyze_router_log.py router.log --total_func "$FUNC_NUM" \
    | tee "logs_fig10/native_${FUNC_NUM}_result.txt"
