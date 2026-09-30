#!/bin/bash
# Per-model test loop for Table 4 (remoting/swap columns), the Figure 6 Torpor
# bar and the Figure 7 variants. Sourced, not executed, by the run_* scripts.
#
# The caller must set:
#   COLUMN      short name, used for logs_${COLUMN}/ and results_${COLUMN}.txt
#   DRIVER      Python driver run once per model (e.g. swap_PCIe_latency.py)
#   SERVER_SIF  Apptainer server image
# and may set:
#   MODELS            array of models (default: the 8 Table 4 models)
#   EXTRA_SERVER_ENV  appended to the server --env list, e.g. ",BUFFER_SIZE=1"
#
# Every model gets a fresh server. Cleanup runs before each model and on exit,
# because a crashed run leaves processes holding GPU memory and IPC sockets.

set -u

EXTRA_SERVER_ENV="${EXTRA_SERVER_ENV:-}"
echo "[$COLUMN] Using SERVER_SIF=$SERVER_SIF"

if [ -z "${MODELS+x}" ]; then
    MODELS=("densenet169" "densenet201" "inception" "efficientnet" "resnet50" "resnet101" "resnet152" "bertqa")
fi

RESULT_FILE="results_${COLUMN}.txt"
OUTDIR="logs_${COLUMN}"
mkdir -p "$OUTDIR" /dev/shm/ipc
> "$RESULT_FILE"

# Leftovers from an earlier invocation would be stashed under this run's name.
rm -f log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log

# Printed once per GPU executor. The executors share stdout and their lines can
# interleave, so match only this prefix and count occurrences, not lines.
READY_PATTERN="${READY_PATTERN:-Set I/O thread num}"
NUM_GPUS="${NUM_GPUS:-4}"

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

stash_logs() {  # $1 = model name
    local m="$1"
    local f
    for f in log_cuda_server.txt log_client_0.txt client_0.log log_executor_*.txt; do
        [ -e "$f" ] && mv "$f" "$OUTDIR/${f%.*}_${m}.txt"
    done
}

trap cleanup_processes EXIT

for MODEL in "${MODELS[@]}"; do
    echo "=============================="
    echo "[$COLUMN] Testing model: $MODEL"
    echo "=============================="

    cleanup_processes
    LOG_FILE="$OUTDIR/server_log_${MODEL}.txt"

    # Remove a stale log so the readiness check cannot match old markers.
    rm -f "$LOG_FILE"

    apptainer exec --nv \
        --bind /dev/shm/ipc:/cuda \
        --env MEM_LIMIT_IN_GB=25,IO_THREAD_NUM=4${EXTRA_SERVER_ENV} \
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

    echo -n "Running $DRIVER $MODEL ... "
    # 30 min cap: bertqa's client startup is slow, and pyzmq occasionally
    # hangs on exit after the results are printed.
    timeout -k 10 1800 python3 "$DRIVER" "$MODEL" > "$OUTDIR/tmp_output_${MODEL}.txt" 2>&1
    echo "done."
    sleep 3

    LATENCY_LINE=$(grep "Latency avg" "$OUTDIR/tmp_output_${MODEL}.txt" || true)
    END2END_LINE=$(grep "End2End avg" "$OUTDIR/tmp_output_${MODEL}.txt" || true)

    {
        echo "Model: $MODEL"
        if [ -n "$LATENCY_LINE" ]; then
            echo "$LATENCY_LINE"
            echo "$END2END_LINE"
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
