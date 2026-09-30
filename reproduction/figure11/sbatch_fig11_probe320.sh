#!/bin/bash
#SBATCH --job-name=fig11-probe320
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=00:40:00
#SBATCH --output=logs_batch/probe320-%j.out
#SBATCH --error=logs_batch/probe320-%j.err
#
# DIAGNOSTIC ONLY, not a Figure 11 result.
#
# Runs the Figure 11 workload at 320 functions with a 5-minute replay, to
# check whether a short run reproduces the failure of the 31-minute runs.
# Prints device-assert and registration-marker counts, registration windows,
# same-server request overlaps and the warm-up outputs per server, then keeps
# the logs in logs_batch/probe320-<jobid>_logs/.
# Set SERVER_BIN to test a patched server binary (see ../diagnostics/).
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_fig11_probe320.sh
set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh
source "$TORPOR/venv/bin/activate"

# A server crash at this scale writes a core dump of about 100 GB.
ulimit -c 0

# Same tmpfs staging as sbatch_figure11.sh.
MODEL_SRC="$TORPOR/models"
export MODEL_CACHE_DIR=/dev/shm/models
rm -rf "$MODEL_CACHE_DIR"; mkdir -p "$MODEL_CACHE_DIR"
cp -r "$MODEL_SRC/torch" "$MODEL_SRC/hf" "$MODEL_CACHE_DIR/" || { echo "staging failed"; exit 1; }
trap 'rm -rf "$MODEL_CACHE_DIR"' EXIT

export MINUTES=5
export KEEP_LOGS=1
export SERVER_BIN="${SERVER_BIN:-}"
# A crash during client startup is part of what this probe measures, so no retry.
export LAUNCH_ATTEMPTS=1

FUNC_NUM=320
VARIANT=torpor
PROC_DIR="logs_fig11/${VARIANT}_${FUNC_NUM}f_proc"

echo "=== fig11 probe: mixed workload, $FUNC_NUM functions, $MINUTES min replay ==="
echo "started $(date)"
./run_fig11_variant.sh "$VARIANT" "$FUNC_NUM"
echo "run_fig11_variant exit=$?"

echo
echo "=== VERDICT ==="
printf "  indexSelectLargeIndex  : %s   (0 = bertqa never read a bad index)\n" "$(grep -c indexSelectLargeIndex server.log 2>/dev/null)"
printf "  cuda assert            : %s   (0 = context healthy)\n"              "$(grep -c 'cuda assert' server.log 2>/dev/null)"
printf "  fails to find malloc   : %s\n"                                      "$(grep -c 'fails to find malloc' server.log 2>/dev/null)"
printf "  parameter ptr not found: %s\n"                                      "$(grep -c 'parameter ptr not found' server.log 2>/dev/null)"

# Unpaired Track/Untrack lines per executor. This undercounts: "Untrack memory
# for" is logged even when no registration happened. Trust the marker counts
# above more than this number.
echo "  --- registration windows (load-time race) ---"
found_exec=0
for i in 0 1 2 3; do
  f="$PROC_DIR/log_executor_$i.txt"
  [ -f "$f" ] || continue
  found_exec=1
  printf "  exec %s: %s Track / %s Untrack / clobbers: " "$i" \
    "$(grep -c 'Track memory for' "$f")" "$(grep -c 'Untrack memory for' "$f")"
  grep -E "Track memory for|Untrack memory for" "$f" | sed 's/.*\[info\] //' \
   | awk '{if($1=="Track"){if(cur!=""){n++} cur=$4} else {cur=""}} END{print n+0}'
done
[ "$found_exec" -eq 1 ] || echo "  WARNING: no log_executor_*.txt in $PROC_DIR -- clobber count UNKNOWN, not zero"

# Counts requests that started on a server while another request was still
# running there, from the logged query time. This shell version gave
# inconsistent counts; the numbers in the report were recomputed in Python.
echo "  --- same-server request overlap (execution-time race) ---"
grep -o "^[0-9-]*,[0-9:.]*: Func [0-9]* batch size [0-9]* on server [0-9]* end-to-end time: [0-9.]*, issue: [0-9.]*, query: [0-9.]*" router.log 2>/dev/null \
 | sed -E 's/^[0-9-]*,([0-9]{2}):([0-9]{2}):([0-9.]+): Func ([0-9]+) .* on server ([0-9]+) .*query: ([0-9.]+)/\1 \2 \3 \4 \5 \6/' \
 | awk '{end=$1*3600+$2*60+$3; print $5, end-$6, end, $4}' | sort -k1,1n -k2,2n \
 | awk '{s=$1; st=$2; en=$3; f=$4;
         if(s!=ps){mx=0}
         if(st<mx){ov[s]++; tot++; if(f%8==7)bert++}
         if(en>mx)mx=en; ps=s; n[s]++}
        END{t=0; for(i=0;i<4;i++)t+=n[i];
            for(i=0;i<4;i++) printf "  server %d: %6d requests, %4d overlapping\n", i, n[i]+0, ov[i]+0;
            printf "  TOTAL: %d requests, %d overlaps (%d on bertqa)\n", t, tot+0, bert+0;
            if(tot+0==0) print "  >>> ZERO OVERLAPS: probe is NOT in the risky regime, same blind spot as the 40f probe"}'

echo "  --- warm-up (all 4 servers should agree; authors: 0.002658843994140625 / 0.0016798973083496094 / 0.001995086669921875 / 0.004665374755859375 / 0.0028100013732910156 / -21.923080444335938 / 15.960777282714844 / -1725.393798828125) ---"
grep "Warm-up server" router.log 2>/dev/null \
 | sed -E 's/.*server ([0-9]+) func ([0-9]+).*output: ([^,]+),.*/\2 \1 \3/' \
 | awk '{o[$1"_"$2]=$3} END{for(i=0;i<8;i++){s=(o[i"_0"]!=""&&o[i"_0"]==o[i"_1"]&&o[i"_1"]==o[i"_2"]&&o[i"_2"]==o[i"_3"]);
     printf "    func %d: %-22s %-22s %-22s %-22s %s\n",i,o[i"_0"],o[i"_1"],o[i"_2"],o[i"_3"],(s?"CONSISTENT":"DIVERGED")}}'

# Keep this run's logs from being overwritten by the next probe.
STASH="logs_batch/probe320-${SLURM_JOB_ID}_logs"
mkdir -p "$STASH"
cp -a server.log router.log "$STASH/" 2>/dev/null
[ -d "$PROC_DIR" ] && cp -a "$PROC_DIR" "$STASH/" 2>/dev/null
echo "  logs stashed in $STASH"
echo "finished $(date)"
