# Figure 11: policy ablation with mixed models (4 GPUs)

SLO compliance, i.e. the share of functions whose P98 latency is within 80 ms
(CV models) or 200 ms (bertqa), at 320/400/480/560 functions over 8 mixed
models (`router.py -m mixed`: function *i* runs model *i* mod 8 out of
resnet50/101/152, densenet169/201, inception, efficientnet, bertqa). Each run
replays a 31-minute Azure-trace workload. Five variants differ in one knob:

| Variant  | Paper name    | Change against Torpor                 |
|----------|---------------|---------------------------------------|
| `torpor` | Torpor        | none (SLO-aware queueing, `-p sa`)     |
| `fifo`   | Torpor-FIFO   | router `-p fifo`                      |
| `block`  | Torpor-Block  | server env `BLOCK_MANAGER=Fixed`      |
| `lru`    | Torpor-LRU    | server env `EVICT_POLICY=LRU`         |
| `random` | Torpor-Random | server env `SCHEDULE_POLICY=RAND`     |

`random` runs at 320 and 400 only, as annotated in upstream's
`evaluation/figure11/Figure11_README.md` (override with `RANDOM_MAX_FUNC`).

The trace is generated once per function count and cached as
`../../tools/req_arrivals_<n>_31min_trace.npy`, so all variants at one count
see the same requests. General porting notes are in
[`../README.md`](../README.md).

> **Status:** this figure was not reproduced. At 320 functions the server
> crashes during the replay. See "Known problems in the results" in
> `../README.md` and [`../diagnostics/`](../diagnostics/).

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_figure11.sh          # 320 400 480 560 (~18 h)
mkdir -p logs_batch && sbatch -A <project> sbatch_figure11.sh 320 400  # or a subset per job
# or interactively on a compute node, venv active:
./run_all_figure11.sh <FUNC_NUM>   # every variant at one count (KEEP_LOGS=1 keeps old logs)
```

Chunked jobs must run one after the other, never at the same time. They share
this directory (`router.log`, `server.log`, `logs_fig11/`), and
`kill_stale_processes` kills by process name, not by job:

```bash
JOB=$(sbatch --parsable sbatch_figure11.sh 320 400)
sbatch --dependency=afterany:$JOB sbatch_figure11.sh 480 560
```

## Individual runs

```bash
./run_fig11_variant.sh <variant> <FUNC_NUM>   # e.g. ./run_fig11_variant.sh lru 560
```

Client startup alone takes about 30 minutes at 560 functions. The router
starts one client per GPU at a time and waits for its model to load.

The launch phase is retried up to `LAUNCH_ATTEMPTS` (default 3) times. A crash
during the replay fails the run, because a partial `router.log` would still
parse into a plausible result. Failed attempts are kept in
`logs_fig11/<variant>_<n>f_attempt<i>/`.

The sbatch scripts copy the model weights to `/dev/shm/models` and export
`MODEL_CACHE_DIR`. Faster loads lower the rate of the load-time registration
race, but do not eliminate it.

Outputs: `logs_fig11/<variant>_<n>f_result.txt` (SLO summary),
`<variant>_<n>f.log` and `<variant>_<n>f_server.log` (router and server logs),
and `<variant>_<n>f_proc/` with that variant's per-process logs.

The analyzer is upstream's, unchanged. Its "Total function count" line is the
number of functions that appear in `router.log`, not FUNC_NUM. Check that the
two agree: if clients failed to register, the percentage is computed over
fewer functions without any warning.

## Diagnostic probes

`sbatch_fig11_probe.sh` (40 functions, 5 min) and `sbatch_fig11_probe320.sh`
(320 functions, 5 min) are short diagnostic runs, not Figure 11 results. They
print device-assert and registration-marker counts, same-server request
overlaps and the per-server warm-up outputs. **Never judge a Figure 11 run by
completion or latency alone:** after a device-side assert the CUDA context is
dead, and requests return quickly with wrong results, which improves the
apparent SLO. Check that `grep -c indexSelectLargeIndex server.log` and
`grep -c 'cuda assert' server.log` are both 0.
