#!/bin/bash
# Figure 6, "w/o batch" bar. The driver runs inside torpor-client-nobatch.sif,
# which is built with queryBufferSize=1 in async_sender.hpp (upstream edits
# that file inside the container; SIF images are read-only, see ../images/).
# Usage: ./run_fig6_nobatch.sh   (compute node, venv active)
set -u
cd "$(dirname "$0")"
source ../common/env.sh

COLUMN="fig6_nobatch"
MODELS=(resnet152 bertqa)
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
CLIENT_SIF="${CLIENT_SIF:-$TORPOR/images/torpor-client-nobatch.sif}"
echo "[$COLUMN] Using SERVER_SIF=$SERVER_SIF CLIENT_SIF=$CLIENT_SIF"

# See ../common/model_loop.sh for why this is matched as a prefix.
READY_PATTERN="Set I/O thread num"
NUM_GPUS=4

OUTDIR="logs_${COLUMN}"
RESULT_FILE="results_${COLUMN}.txt"
mkdir -p "$OUTDIR"
:> "$RESULT_FILE"

cleanup_processes() {
    pkill -f start_with_server_id 2>/dev/null
    pkill -f start_with_id.sh 2>/dev/null
    pkill -f 'endpoint.py 9' 2>/dev/null
    pkill -f '/server_bin/server' 2>/dev/null
    sleep 3
    pkill -KILL -f 'endpoint.py 9' 2>/dev/null
    pkill -KILL -f '/server_bin/server' 2>/dev/null
    sleep 1
    rm -f /dev/shm/ipc/*
}
trap cleanup_processes EXIT

stash_logs() {  # $1 = model name
    local m="$1"
    mv "$OUTDIR/tmp_output_${m}.txt" "$OUTDIR/driver_output_${m}.txt" 2>/dev/null
    # the driver runs with cwd fig6_nobatch/, so its client log lands there
    [ -e fig6_nobatch/log_client_0.txt ] && mv fig6_nobatch/log_client_0.txt "$OUTDIR/log_client_0_${m}.txt"
}

for MODEL in "${MODELS[@]}"; do
    echo "=============================="
    echo "[$COLUMN] Testing model: $MODEL"
    echo "=============================="

    cleanup_processes
    mkdir -p /dev/shm/ipc

    LOG_FILE="$OUTDIR/server_log_${MODEL}.txt"

    # Remove a stale log so the readiness check cannot match old markers.
    rm -f "$LOG_FILE"

    apptainer exec --nv \
        --bind /dev/shm/ipc:/cuda \
        --env MEM_LIMIT_IN_GB=25,IO_THREAD_NUM=4 \
        "$SERVER_SIF" \
        bash -c 'LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH LD_PRELOAD=/server_bin/libwapper.so /server_bin/server' \
        > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!

    echo "Waiting for server readiness..."
    READY=0
    for i in {1..120}; do
        if [ "$(grep -o "$READY_PATTERN" "$LOG_FILE" 2>/dev/null | wc -l)" -ge "$NUM_GPUS" ]; then
            READY=1
            break
        fi
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "FATAL: server died during startup, see $LOG_FILE" | tee -a "$RESULT_FILE"
            exit 1
        fi
        sleep 2
    done
    if [ "$READY" -ne 1 ]; then
        echo "FATAL: server not ready after 240s, see $LOG_FILE" | tee -a "$RESULT_FILE"
        exit 1
    fi
    echo "Server is ready."
    sleep 5

    echo -n "Running torpor_without_batch.py (model_name=$MODEL) inside $CLIENT_SIF ... "

    # 30 min cap: bertqa's client startup is slow
    timeout -k 10 1800 taskset -c 48 apptainer exec \
        --bind /dev/shm/ipc:/cuda \
        --bind "$PWD:/workspace" \
        --pwd /workspace/fig6_nobatch \
        --env model_name=$MODEL,OMP_NUM_THREADS=1,KMP_DUPLICATE_LIB_OK=TRUE,TORCH_HOME=$TORPOR/models/torch,HF_HOME=$TORPOR/models/hf,HF_HUB_OFFLINE=1,TRANSFORMERS_OFFLINE=1 \
        "$CLIENT_SIF" \
        python3 torpor_without_batch.py > "$OUTDIR/tmp_output_${MODEL}.txt" 2>&1
    echo "done."
    sleep 3

    LATENCY_LINE=$(grep "Latency avg" "$OUTDIR/tmp_output_${MODEL}.txt" || true)

    {
        echo "Model: $MODEL"
        if [ -n "$LATENCY_LINE" ]; then
            echo "$LATENCY_LINE"
        else
            echo "FAILED -- inspect $OUTDIR/tmp_output_${MODEL}.txt and $OUTDIR/*_${MODEL}.txt"
        fi
        echo
    } >> "$RESULT_FILE"

    cleanup_processes
    stash_logs "$MODEL"
    echo
done

echo "=============================="
echo "[$COLUMN] All results collected:"
echo "=============================="
cat "$RESULT_FILE"
