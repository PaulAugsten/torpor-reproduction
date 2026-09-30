#!/bin/bash
#SBATCH --job-name=fig11-probe
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=00:25:00
#SBATCH --output=logs_batch/probe-%j.out
#SBATCH --error=logs_batch/probe-%j.err
#
# DIAGNOSTIC ONLY, not a Figure 11 result.
#
# Runs Figure 11's mixed workload (bertqa included) at Figure 10's scale:
# 40 functions, 5-minute replay. This separates the workload from scale and
# duration as the cause of the Figure 11 failure. Prints device-assert and
# registration-marker counts and the warm-up outputs per server.
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_fig11_probe.sh
set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh
source "$TORPOR/venv/bin/activate"

# Same tmpfs staging as sbatch_figure11.sh.
MODEL_SRC="$TORPOR/models"
export MODEL_CACHE_DIR=/dev/shm/models
rm -rf "$MODEL_CACHE_DIR"; mkdir -p "$MODEL_CACHE_DIR"
cp -r "$MODEL_SRC/torch" "$MODEL_SRC/hf" "$MODEL_CACHE_DIR/" || { echo "staging failed"; exit 1; }
trap 'rm -rf "$MODEL_CACHE_DIR"' EXIT

export MINUTES=5
export KEEP_LOGS=1

echo "=== fig11 probe: mixed workload, 40 functions, 5 min replay ==="
echo "started $(date)"
./run_fig11_variant.sh torpor 40
echo "run_fig11_variant exit=$?"

echo
echo "=== VERDICT ==="
printf "  indexSelectLargeIndex : %s   (0 = bertqa never read a bad index)\n" "$(grep -c indexSelectLargeIndex server.log 2>/dev/null)"
printf "  cuda assert           : %s   (0 = context healthy)\n"              "$(grep -c 'cuda assert' server.log 2>/dev/null)"
printf "  fails to find malloc  : %s\n"                                      "$(grep -c 'fails to find malloc' server.log 2>/dev/null)"
printf "  parameter ptr not found: %s\n"                                     "$(grep -c 'parameter ptr not found' server.log 2>/dev/null)"
# Note: cleanup() in run_fig11_variant.sh has already moved the executor logs
# into logs_fig11/torpor_40f_proc/, so this loop finds nothing (see
# sbatch_fig11_probe320.sh for the corrected version).
for i in 0 1 2 3; do
  [ -f log_executor_$i.txt ] || continue
  printf "  exec %s clobbers: " $i
  grep -E "Track memory for|Untrack memory for" log_executor_$i.txt | sed 's/.*\[info\] //' \
   | awk '{if($1=="Track"){if(cur!=""){n++} cur=$4} else {cur=""}} END{print n+0}'
done
echo "  warm-up (must agree across all 4 servers):"
grep "Warm-up server" router.log 2>/dev/null \
 | sed -E 's/.*server ([0-9]+) func ([0-9]+).*output: ([^,]+),.*/\2 \1 \3/' \
 | awk '{o[$1"_"$2]=$3} END{for(i=0;i<8;i++){s=(o[i"_0"]!=""&&o[i"_0"]==o[i"_1"]&&o[i"_1"]==o[i"_2"]&&o[i"_2"]==o[i"_3"]);
     printf "    func %d: %-22s %-22s %-22s %-22s %s\n",i,o[i"_0"],o[i"_1"],o[i"_2"],o[i"_3"],(s?"CONSISTENT":"DIVERGED")}}'
echo "finished $(date)"
