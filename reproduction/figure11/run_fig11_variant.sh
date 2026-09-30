#!/bin/bash
# Figure 11, one variant at one function count.
# Usage: ./run_fig11_variant.sh <VARIANT> <FUNC_NUM>
#   VARIANT:  torpor | fifo | block | lru | random
#   FUNC_NUM: 320 | 400 | 480 | 560
#
# All variants run the mixed 8-model workload on 4 GPUs with a 31-minute
# Azure-trace replay. They differ in one knob:
#   torpor  SLO-aware queueing (-p sa), default server            (Torpor)
#   fifo    FIFO queueing (-p fifo)                               (Torpor-FIFO)
#   block   server env BLOCK_MANAGER=Fixed                        (Torpor-Block)
#   lru     server env EVICT_POLICY=LRU                           (Torpor-LRU)
#   random  server env SCHEDULE_POLICY=RAND                       (Torpor-Random)
# pipefail so that a crashing analyzer is not hidden behind tee.
set -u -o pipefail
cd "$(dirname "$0")"
source ../common/env.sh
VARIANT=${1:?Usage: $0 <torpor|fifo|block|lru|random> <FUNC_NUM>}
FUNC_NUM=${2:?Usage: $0 <torpor|fifo|block|lru|random> <FUNC_NUM>}
# The paper replays 31 minutes. Shorter values are for diagnostic probes only.
MINUTES=${MINUTES:-31}
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
# Optional server binary bind-mounted over the one in the image (used for the
# diagnostic builds in ../diagnostics/). Unset: the image's own binary.
SERVER_BIN="${SERVER_BIN:-}"
SERVER_BIN_BIND=""
if [ -n "$SERVER_BIN" ]; then
    [ -x "$SERVER_BIN" ] || { echo "ERROR: SERVER_BIN=$SERVER_BIN is not executable"; exit 1; }
    SERVER_BIN_BIND="--bind $SERVER_BIN:/server_bin/server:ro"
fi

POLICY=sa
EXTRA_SERVER_ENV=""
case "$VARIANT" in
    torpor) ;;
    fifo)   POLICY=fifo ;;
    block)  EXTRA_SERVER_ENV=",BLOCK_MANAGER=Fixed" ;;
    lru)    EXTRA_SERVER_ENV=",EVICT_POLICY=LRU" ;;
    random) EXTRA_SERVER_ENV=",SCHEDULE_POLICY=RAND" ;;
    *) echo "ERROR: unknown variant '$VARIANT'"; exit 1 ;;
esac
echo "Using SERVER_SIF=$SERVER_SIF (variant=$VARIANT, policy=$POLICY, extra env='$EXTRA_SERVER_ENV')"
echo "Using SERVER_BIN=${SERVER_BIN:-<stock binary from SIF>}"
mkdir -p logs_fig11
source ../common/kill_stale.sh

# All per-process logs of this variant end up here.
PROC_DIR="logs_fig11/${VARIANT}_${FUNC_NUM}f_proc"

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return 0
    CLEANED=1
    echo "[cleanup] stopping torpor..."
    # Save the logs before killing anything: after scancel or a wall-clock
    # timeout, Slurm sends SIGKILL a few seconds after SIGTERM.
    mkdir -p "$PROC_DIR"
    [ -f router.log ] && cp router.log "logs_fig11/${VARIANT}_${FUNC_NUM}f.log"
    [ -f server.log ] && cp server.log "logs_fig11/${VARIANT}_${FUNC_NUM}f_server.log"
    # A single mv keeps this fast with hundreds of client logs.
    mv -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log \
        "$PROC_DIR/" 2>/dev/null
    rmdir "$PROC_DIR" 2>/dev/null   # leave no empty dir if there was nothing to move
    kill_stale_processes
    rm -rf /dev/shm/ipc
}
trap cleanup EXIT
# EXIT alone does not fire when bash is killed by a signal (scancel, time limit).
trap 'cleanup; exit 143' INT TERM

kill_stale_processes
rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc

# router.log and server.log are removed at the start of every launch attempt
# in start_stack(), so a retry or a later variant never reads stale markers.
rm -f "logs_fig11/${VARIANT}_${FUNC_NUM}f_result.txt"

# The server can crash (see README). Nothing downstream notices on its own, so
# check liveness at every step and print the first registration-failure
# markers from the server log.
server_alive() { kill -0 "$SERVER_PID" 2>/dev/null; }
launch_failed() {
    echo "ERROR: server process died $1"
    if grep -q 'fails to find malloc' server.log 2>/dev/null; then
        echo "       precursor: $(grep -c 'fails to find malloc' server.log)x 'cudaMemcpy model fails to find malloc'"
        grep -m 2 -E 'fails to find malloc|parameter ptr not found' server.log | sed 's/^/       /'
    fi
}

stash_failed_attempt() {
    local dir="logs_fig11/${VARIANT}_${FUNC_NUM}f_attempt$1"
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

    rm -f router.log server.log
    rm -f log_client_*.txt log_executor_*.txt log_cuda_server*.txt router_stdout.log

    # 1. Server on all 4 GPUs, with the variant's settings
    apptainer exec --nv \
        --bind /dev/shm/ipc:/cuda \
        $SERVER_BIN_BIND \
        --env MEM_LIMIT_IN_GB=25,IO_THREAD_NUM=4${EXTRA_SERVER_ENV} \
        "$SERVER_SIF" \
        bash -c 'LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH LD_PRELOAD=/server_bin/libwapper.so /server_bin/server' \
        > server.log 2>&1 &
    SERVER_PID=$!

    # See ../common/model_loop.sh for why this is matched as a prefix.
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

    # 2. Router with the mixed 8-model workload, pinned outside all NUMA_CORES
    # ranges. The clients write their logs directly into PROC_DIR.
    export CLIENT_LOG_DIR="$PROC_DIR"
    mkdir -p "$PROC_DIR"
    taskset -c 200 python3 router.py -m mixed -s 4 -f "$FUNC_NUM" -p "$POLICY" > router_stdout.log 2>&1 &
    ROUTER_PID=$!

    # 3. Wait until all clients are loaded (about 30 min at 560; allow 90)
    echo "Waiting for $FUNC_NUM clients (takes ~30 min at 560)..."
    for i in $(seq 1 2700); do
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

# Let the previous variant's processes release CPUs and GPU memory first.
SETTLE_SECS="${SETTLE_SECS:-30}"
echo "Settling ${SETTLE_SECS}s before start..."
sleep "$SETTLE_SECS"

# Retry the launch phase only (see ../figure9/run_fig9_torpor.sh). A crash
# during the replay still fails the run. Note that the 320-function probe
# crashed during the replay, so for Figure 11 a retry is not bias-free.
LAUNCH_ATTEMPTS="${LAUNCH_ATTEMPTS:-3}"
LAUNCHED=0
for attempt in $(seq 1 "$LAUNCH_ATTEMPTS"); do
    if [ "$attempt" -gt 1 ]; then
        echo "Retrying launch (attempt $attempt / $LAUNCH_ATTEMPTS)..."
        kill_stale_processes
        rm -rf /dev/shm/ipc && mkdir -p /dev/shm/ipc
        sleep 15
    fi
    if start_stack; then
        LAUNCHED=1
        [ "$attempt" -gt 1 ] && echo "Launch succeeded on attempt $attempt."
        break
    fi
    stash_failed_attempt "$attempt"
done
if [ "$LAUNCHED" -ne 1 ]; then
    echo "ERROR: launch failed on all $LAUNCH_ATTEMPTS attempts -- no result for ${VARIANT} at ${FUNC_NUM}f."
    exit 1
fi

# 4. Replay the 31-minute trace (generated once per FUNC_NUM and cached in
# ../../tools, so all variants at one count see the same requests)
python3 sender_from_trace.py "$FUNC_NUM" "$MINUTES" 0 || { echo "sender failed"; exit 1; }
# A partial router.log would still parse into a plausible result.
server_alive || { launch_failed "during the trace replay"; exit 1; }
sleep 10

# 5. Analyze: SLO compliance (80 ms for CV models, 200 ms for bertqa)
python3 figure11_analyze_router_log.py router.log \
    | tee "logs_fig11/${VARIANT}_${FUNC_NUM}f_result.txt"
