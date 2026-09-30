#!/bin/bash
# Figure 9, Torpor run for one random trace (40 resnet152 functions, 4 GPUs,
# SLO-aware policy). Replays the trace cached by the Native run with the same
# TRACE_ID, or generates it if Torpor runs first.
# Usage: ./run_fig9_torpor.sh <TRACE_ID>   (upstream labels: -5 -7 -1 -10)
# pipefail so that a crashing analyzer is not hidden behind tee.
set -u -o pipefail
cd "$(dirname "$0")"
source ../common/env.sh
TRACE_ID=${1:?Usage: $0 <TRACE_ID (e.g. -5)>}
FUNC_NUM=40
MINUTES=5
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
# Optional prefix for the server command, e.g. "numactl --interleave=all".
SERVER_LAUNCH_PREFIX="${SERVER_LAUNCH_PREFIX:-}"
echo "Using SERVER_SIF=$SERVER_SIF"
[ -n "$SERVER_LAUNCH_PREFIX" ] && echo "Server launch prefix: $SERVER_LAUNCH_PREFIX"
mkdir -p logs_fig9
source ../common/kill_stale.sh

cleanup() {
    echo "[cleanup] stopping torpor..."
    [ -n "${SAMPLER_PID:-}" ] && kill "$SAMPLER_PID" 2>/dev/null
    kill_stale_processes
    rm -rf /dev/shm/ipc
    [ -f router.log ] && cp router.log "logs_fig9/torpor_trace${TRACE_ID}.log"
    [ -f server.log ] && cp server.log "logs_fig9/torpor_trace${TRACE_ID}_server.log"
    PROC_DIR="logs_fig9/torpor_trace${TRACE_ID}_proc"
    for f in log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log; do
        [ -e "$f" ] || continue
        mkdir -p "$PROC_DIR" && mv "$f" "$PROC_DIR/"
    done
}
trap cleanup EXIT

kill_stale_processes
rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc

rm -f "logs_fig9/torpor_trace${TRACE_ID}_result.txt"

NODE_STATE="logs_fig9/torpor_trace${TRACE_ID}_nodestate.txt"
: > "$NODE_STATE"

# Record leftover processes and GPU state before each attempt. Processes from
# the preceding run that are still winding down inflate the measured latency.
record_node_state() {
    local leftovers
    leftovers=$(pgrep -af 'baseline_native.py|baseline_keepalive.py|router\.py|endpoint\.py|/server_bin/server' || true)
    {
        echo "=== $(date -Is) before torpor trace ${TRACE_ID}, attempt $1 ==="
        echo "--- leftover experiment processes (should be none) ---"
        echo "${leftovers:-(none)}"
        echo "--- load average ---"
        cat /proc/loadavg
        echo "--- nvidia-smi ---"
        nvidia-smi
        echo
    } >> "$NODE_STATE" 2>&1
    [ -n "$leftovers" ] && echo "WARNING: experiment processes still running at start -- see $NODE_STATE"
    return 0
}

# Record where the server's executor threads run. Clients and router are
# pinned; the server threads are the only ones the OS places freely.
PLACEMENT="logs_fig9/torpor_trace${TRACE_ID}_placement.txt"
: > "$PLACEMENT"

capture_topology() {
    {
        echo "=== GPU -> local CPU mapping on $(hostname) ==="
        nvidia-smi --query-gpu=index,pci.bus_id --format=csv,noheader 2>/dev/null |
        while IFS=, read -r idx bus; do
            bus=$(echo "$bus" | tr -d ' ' | tr 'A-F' 'a-f')
            short="${bus:4}"
            echo "GPU $idx  $short  numa_node=$(cat "/sys/bus/pci/devices/$short/numa_node" 2>/dev/null || echo n/a)  local_cpulist=$(cat "/sys/bus/pci/devices/$short/local_cpulist" 2>/dev/null || echo n/a)"
        done
        echo "--- cores router.py pins clients to (NUMA_CORES) ---"
        echo "GPU0=48-63  GPU1=16-31  GPU2=112-127  GPU3=80-95"
        echo "--- numactl -H ---"
        numactl -H 2>/dev/null || echo "(numactl not available)"
        echo
    } >> "$PLACEMENT" 2>&1
}

capture_placement() {
    {
        echo "=== $(date -Is)  $1 ==="
        local srv
        srv=$(pgrep -f '/server_bin/server' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if [ -n "$srv" ]; then
            ps -Lo pid,tid,psr,pcpu,comm -p "$srv" 2>&1
        else
            echo "(no /server_bin/server process found)"
        fi
        echo
    } >> "$PLACEMENT" 2>&1
}

# The server can crash during model loading (see README). Nothing downstream
# notices on its own, so check liveness at every step and print the first
# registration-failure markers from the server log.
server_alive() { kill -0 "$SERVER_PID" 2>/dev/null; }
launch_failed() {
    echo "ERROR: server process died $1"
    if grep -q 'fails to find malloc' server.log 2>/dev/null; then
        echo "       precursor: $(grep -c 'fails to find malloc' server.log)x 'cudaMemcpy model fails to find malloc'"
        grep -m 2 -E 'fails to find malloc|parameter ptr not found' server.log | sed 's/^/       /'
    fi
}

stash_failed_attempt() {
    local dir="logs_fig9/torpor_trace${TRACE_ID}_attempt$1"
    mkdir -p "$dir"
    [ -f server.log ] && cp server.log "$dir/server.log"
    [ -f router.log ] && cp router.log "$dir/router.log"
    for f in log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log; do
        [ -e "$f" ] || continue
        mv "$f" "$dir/"
    done
    echo "       evidence kept in $dir/"
}

# Steps 1-3: start the server and load all FUNC_NUM functions.
# Returns non-zero if that did not succeed.
start_stack() {
    local i ready_srv=0 ready=0

    # Remove stale logs so the readiness checks cannot match old markers.
    rm -f router.log server.log
    rm -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log

    # 1. Server on all 4 GPUs
    ${SERVER_LAUNCH_PREFIX} apptainer exec --nv \
        --bind /dev/shm/ipc:/cuda \
        --env MEM_LIMIT_IN_GB=25,IO_THREAD_NUM=4 \
        "$SERVER_SIF" \
        bash -c 'LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH LD_PRELOAD=/server_bin/libwapper.so /server_bin/server' \
        > server.log 2>&1 &
    SERVER_PID=$!

    echo "Waiting for server readiness..."
    for i in $(seq 1 120); do
        if [ "$(grep -o 'Set I/O thread num' server.log 2>/dev/null | wc -l)" -ge 4 ]; then
            ready_srv=1; break
        fi
        server_alive || { launch_failed "during server startup"; return 1; }
        sleep 2
    done
    if [ "$ready_srv" -ne 1 ]; then
        echo "ERROR: server not ready after 240s, see server.log"; return 1
    fi
    echo "Server is ready."
    sleep 5

    # 2. Router; it launches the clients.
    taskset -c 200 python3 router.py -m resnet152 -s 4 -f "$FUNC_NUM" -p sa > router_stdout.log 2>&1 &
    ROUTER_PID=$!

    # 3. Wait until all clients are loaded
    echo "Waiting for $FUNC_NUM clients..."
    for i in $(seq 1 900); do
        ready=$(grep -c 'ExecuteAfterLoad .* resp' router.log 2>/dev/null)
        ready=${ready:-0}
        [ "$ready" -ge "$FUNC_NUM" ] && break
        server_alive || { launch_failed "during client startup (loaded $ready / $FUNC_NUM)"; return 1; }
        sleep 2
    done
    echo "Clients ready: $ready / $FUNC_NUM"
    if [ "$ready" -lt "$FUNC_NUM" ]; then
        echo "ERROR: client startup incomplete"; return 1
    fi
    return 0
}

SETTLE_SECS="${SETTLE_SECS:-30}"
echo "Settling ${SETTLE_SECS}s before start..."
sleep "$SETTLE_SECS"

# Retry the launch phase only. All crashes observed in Figure 9 happened
# before the first trace request, so a retry cannot bias the measurement. A
# crash during the replay still fails the run (step 4).
LAUNCH_ATTEMPTS="${LAUNCH_ATTEMPTS:-5}"
LAUNCHED=0
for attempt in $(seq 1 "$LAUNCH_ATTEMPTS"); do
    if [ "$attempt" -gt 1 ]; then
        echo "Retrying launch (attempt $attempt / $LAUNCH_ATTEMPTS)..."
        kill_stale_processes
        rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc
        sleep 15
    fi
    record_node_state "$attempt"
    if start_stack; then
        LAUNCHED=1
        [ "$attempt" -gt 1 ] && echo "Launch succeeded on attempt $attempt."
        break
    fi
    stash_failed_attempt "$attempt"
done
if [ "$LAUNCHED" -ne 1 ]; then
    echo "ERROR: launch failed on all $LAUNCH_ATTEMPTS attempts -- no result for trace ${TRACE_ID}."
    exit 1
fi

capture_topology
capture_placement "clients ready, before replay"

# 4. Replay the same trace as the Native run, sampling thread placement once
# per minute.
( while true; do sleep 60; capture_placement "during replay"; done ) &
SAMPLER_PID=$!
python3 sender_fix_rate.py "$FUNC_NUM" "$MINUTES" 0 "$TRACE_ID" || { kill "$SAMPLER_PID" 2>/dev/null; echo "sender failed"; exit 1; }
kill "$SAMPLER_PID" 2>/dev/null; SAMPLER_PID=""
capture_placement "replay finished"
# A partial router.log would still parse into a plausible result.
server_alive || { launch_failed "during the trace replay"; exit 1; }
sleep 10

# 5. Analyze: per-GPU normalized load and P98 latency
python3 figure9_analyze_router_log.py router.log \
    | tee "logs_fig9/torpor_trace${TRACE_ID}_result.txt"
