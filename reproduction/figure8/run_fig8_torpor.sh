#!/bin/bash
# Figure 8, one Torpor point on a single GPU.
# Usage: ./run_fig8_torpor.sh <FUNC_NUM> <RATE>
# Upstream pairs: (33,80) (40,60) (60,40) (120,20) (210,10)
set -u -o pipefail
cd "$(dirname "$0")"
source ../common/env.sh
FUNC_NUM=${1:?Usage: $0 <FUNC_NUM> <RATE>}
RATE=${2:?Usage: $0 <FUNC_NUM> <RATE>}
MINUTES=5
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
echo "Using SERVER_SIF=$SERVER_SIF"
mkdir -p logs_fig8
source ../common/kill_stale.sh

cleanup() {
    echo "[cleanup] stopping torpor..."
    kill_stale_processes
    rm -rf /dev/shm/ipc
    [ -f router.log ] && cp router.log "logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm.log"
    [ -f server.log ] && cp server.log "logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm_server.log"
    PROC_DIR="logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm_proc"
    for f in log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log core.*; do
        [ -e "$f" ] || continue
        mkdir -p "$PROC_DIR" && mv "$f" "$PROC_DIR/"
    done
}
trap cleanup EXIT

kill_stale_processes
rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc

# Remove the previous run's logs first. router.py truncates router.log only
# once it has started, and the readiness loop below reads it immediately, so a
# stale log would let the sender start before the models are loaded.
rm -f router.log server.log
rm -f "logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm_result.txt"
rm -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log

# 1. Server, restricted to GPU 0
apptainer exec --nv \
    --bind /dev/shm/ipc:/cuda \
    --env CUDA_VISIBLE_DEVICES=0,MEM_LIMIT_IN_GB=25,IO_THREAD_NUM=4 \
    "$SERVER_SIF" \
    bash -c 'ulimit -c unlimited; LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH LD_PRELOAD=/server_bin/libwapper.so /server_bin/server' \
    > server.log 2>&1 &
SERVER_PID=$!

# The server can crash mid-run, and nothing downstream notices: the clients
# just time out, and a partial router.log still parses. Check at every step.
server_alive() { kill -0 "$SERVER_PID" 2>/dev/null; }
server_died() {
    echo "ERROR: server process died $1 -- see server.log,"
    echo "       logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm_proc/ and any core.* file."
    exit 1
}

# One executor (single GPU). See ../common/model_loop.sh for the prefix match.
echo "Waiting for server readiness..."
READY_SRV=0
for i in $(seq 1 120); do
    if [ "$(grep -o 'Set I/O thread num' server.log 2>/dev/null | wc -l)" -ge 1 ]; then
        READY_SRV=1; break
    fi
    server_alive || server_died "during startup"
    sleep 2
done
if [ "$READY_SRV" -ne 1 ]; then
    echo "ERROR: server not ready after 240s, see server.log"; exit 1
fi
echo "Server is ready."
sleep 5

# 2. Router with -s 1; it launches the clients.
# Pinned to a core outside all NUMA_CORES ranges so the clients cannot starve it.
taskset -c 200 python3 router.py -m resnet152 -s 1 -f "$FUNC_NUM" -p sa > router_stdout.log 2>&1 &
ROUTER_PID=$!

# 3. Wait until all clients are loaded
echo "Waiting for $FUNC_NUM clients (this takes a while at high N)..."
READY=0
for i in $(seq 1 1800); do
    READY=$(grep -c 'ExecuteAfterLoad .* resp' router.log 2>/dev/null)
    READY=${READY:-0}
    [ "$READY" -ge "$FUNC_NUM" ] && break
    server_alive || server_died "during client startup (loaded $READY / $FUNC_NUM)"
    sleep 2
done
echo "Clients ready: $READY / $FUNC_NUM"
[ "$READY" -lt "$FUNC_NUM" ] && { echo "ERROR: client startup incomplete"; exit 1; }

# 4. Send at the fixed per-function rate
python3 sender_fix_rate.py "$FUNC_NUM" "$MINUTES" 0 "$RATE" || { echo "sender failed"; exit 1; }
server_alive || server_died "during the send phase"
sleep 10

# 5. Analyze
python3 figure8_analyze_router_log.py router.log \
    | tee "logs_fig8/torpor_${FUNC_NUM}f_${RATE}rpm_result.txt"
