# Figure 9: load balancing across GPUs (4 GPUs)

40 high-frequency resnet152 functions on four GPUs. Native binds functions
statically to GPUs while Torpor binds late. The analyzer reports normalized
per-GPU load and per-GPU P98 latency.

Each run replays a random trace for 5 minutes: per-function rates are drawn
from the Azure invocation pattern and multiplied by 10. Original uses four such
traces, labelled by the negative "rate" argument: -5, -7, -1, -10. A trace is
generated on first use and cached as `../../tools/req_arrivals_40_5_<id>.npy`,
so Native and Torpor with the same label replay identical requests. The label
is only a cache key, not a random seed, so a new run with an empty cache draws
new traces. The traces used for the reported results are in the Zenodo data
record.

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_figure9.sh
# or interactively on a compute node, venv active:
./run_all_figure9.sh             # wipes previous logs first (KEEP_LOGS=1 keeps them)
```

## Individual runs

```bash
./run_fig9_native.sh <TRACE_ID>   # e.g. ./run_fig9_native.sh -5
./run_fig9_torpor.sh <TRACE_ID>   # e.g. ./run_fig9_torpor.sh -5
```

`router.py` and `baseline_native.py` are the same as in `../figure10/`. `sender_fix_rate.py` is the original's Figure 9 version with
only `data_path` adjusted, and the analyzer is original's, unchanged.

Outputs: `logs_fig9/<variant>_trace<id>_result.txt` (per-GPU load and P98
tables), plus the router and server logs of each run next to them.
