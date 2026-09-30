#!/bin/bash
# Figure 8, all points on a single GPU.
#   Native: 19 functions at 80/60/40/20/10 rpm each (20 rpm is an addition to
#           upstream's list).
#   Torpor: (func_num, rpm) = (33,80) (40,60) (60,40) (120,20) (210,10).
# Usage: ./run_all_figure8.sh   (compute node, venv active)
# Set KEEP_LOGS=1 to keep the logs of the previous run. Export SERVER_SIF to
# use a different server image for the Torpor points.
set -u
cd "$(dirname "$0")"

if [ "${KEEP_LOGS:-0}" != "1" ]; then
    rm -rf logs_fig8
    rm -f router.log server.log baseline.log router_stdout.log \
          log_cuda_server*.txt log_executor_*.txt log_client_*.txt client_*.log
fi

NATIVE_RATES=(80 60 40 20 10)
TORPOR_POINTS=("33 80" "40 60" "60 40" "120 20" "210 10")

STEPS=()
for r in "${NATIVE_RATES[@]}"; do
    STEPS+=("./run_fig8_native.sh $r")
done
for p in "${TORPOR_POINTS[@]}"; do
    STEPS+=("./run_fig8_torpor.sh $p")
done

FAILED=()
for s in "${STEPS[@]}"; do
    echo "###### $s ######"
    bash -c "$s" || FAILED+=("$s")
    echo
done

echo "===== Figure 8: all points ====="
for r in "${NATIVE_RATES[@]}"; do
    f="logs_fig8/native_19f_${r}rpm_result.txt"
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done
for p in "${TORPOR_POINTS[@]}"; do
    read -r n r <<< "$p"
    f="logs_fig8/torpor_${n}f_${r}rpm_result.txt"
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo; }
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "FAILED steps: ${FAILED[*]}"
    exit 1
fi
