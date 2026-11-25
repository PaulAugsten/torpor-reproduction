# Figure 8: GPU efficiency for low-frequency functions (single GPU)

Fixed-rate traffic on one GPU. Native binds at most 19 resnet152 instances to
the GPU while Torpor swaps many more functions onto it.

- Native: 19 functions at 80 / 60 / 40 / 20 / 10 rpm each (original lists
  80/60/40/10)
- Torpor: (functions, rpm) = (33,80) (40,60) (60,40) (120,20) (210,10)

Each run sends traffic for 5 minutes
(`sender_fix_rate.py <func_num> 5 0 <rate>`) and reports P98 latency and
throughput with `figure8_analyze_router_log.py`.

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_figure8.sh
# or interactively on a compute node, venv active:
./run_all_figure8.sh             # wipes previous logs first (KEEP_LOGS=1 keeps them)
```

## Individual points

```bash
./run_fig8_native.sh <RATE> [FUNC_NUM=19]   # e.g. ./run_fig8_native.sh 80
./run_fig8_torpor.sh <FUNC_NUM> <RATE>      # e.g. ./run_fig8_torpor.sh 33 80
```

The Torpor server is restricted to GPU 0 (`CUDA_VISIBLE_DEVICES=0`). Unlike Figures 9 to 11, the Figure 8 router has no 2 s
pause between client launches.

Outputs: `logs_fig8/<variant>_<n>f_<rate>rpm_result.txt` (summaries), plus the
router and server logs of each run next to them.

## Deviations from the original

- **Native baseline server mapping.** `get_server_id()` in
  `baseline_native.py` returns `client_id % server_num` instead of the
  hardcoded `client_id % 4` from the original. With `-s 1`, the original starts only manager 0, so
  every function with `id % 4 != 0` (14 of 19) is pushed into an unbound ZMQ
  socket and never served. At 40 to 80 rpm the queued pushes also reach ZMQ's
  1000-message high-water mark and block the router mid-run. With `-s 4`
  (Figures 9 and 10) both expressions are identical.
- **Trace cache keyed by rate.** Original `sender_fix_rate.py` caches the
  trace as `req_arrivals_<n>_<mins>.npy`, so the Native runs (same function
  count, different rates) would replay the first rate's trace. The port uses
  `req_arrivals_<n>_<mins>min_<rpm>rpm.npy`.
