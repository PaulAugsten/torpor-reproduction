# Torpor reproduction on JURECA (Apptainer / Slurm, 4x A100)

This directory contains a reproduction of the single-node evaluation of the
Torpor paper (TODO: full citation) using the authors' artifact
([s4-lab-cuhksz/torpor](https://github.com/s4-lab-cuhksz/torpor)). The
upstream evaluation is a set of Docker commands for a 4x V100 cloud VM. Here
it is ported to Apptainer and Slurm and run on one JURECA DC-GPU node at the
Jülich Supercomputing Centre (4x NVIDIA A100-40GB, 2x AMD EPYC 7742).

- Author: Paul Augsten, University of Cologne
- Runs: July to September 2026
- Raw logs and result files: Zenodo, DOI: TODO

Everything outside `reproduction/` is upstream code, with one exception: the
one-line `host_addr` fix in `include/server/model_repo.hpp` (see
[Server](#server)).

## Results

The upstream artifact contains only the single-node prototype, so the
reproducible scope is Table 4 and Figures 6 to 11 (paper Sections 7.1 to 7.3).
All seven were ported and run. Absolute latencies differ from the paper
(different GPUs); what can be compared are the relations between bars and
the trends.

| Artifact | Status | Main result | Slurm job(s) |
|---|---|---|---|
| Table 4 | Reproduced | Remoting overhead 0 to 10% for the ResNets, +61% for bertqa; NVLink swap 1.0 to 1.9x faster than PCIe | 15526825 |
| Figure 6 | Reproduced (2 of 3 bars) | Batching CUDA calls: 3.2x (resnet152) and 2.1x (bertqa) lower latency. The GVirtuS bar has no code in the artifact | 15514443 |
| Figure 7 | Partly | resnet152: every step helps (46.7, 30.4, 25.0, 23.8 ms). bertqa: +Pipeline step is flat | 15514450 |
| Figure 8 | Reproduced, after a baseline fix | Torpor serves 210 functions on one GPU at 39 ms P98 against 19 for Native; 11x throughput at 10 rpm | Torpor 15515117, Native 15667192 |
| Figure 9 | Partly | Torpor load CoV 0.04 to 0.14 against 0.24 to 0.57 for Native. The Native tail penalty is much smaller than in the paper (GPUs far from saturation, different random traces) | 15518911 (repeat: 15518765) |
| Figure 10 | Reproduced | Torpor 100% SLO at 40 to 160 functions; Native 100/90/60/45%; INFless-KA 16 to 31%. At 160 functions 40% of Torpor's outputs are wrong (see below) | 15518439 |
| Figure 11 | Not reproduced | The server crashes at 320 functions. Most likely cause: a race on per-server state in `cuda_server.hpp` | probes 15599058, 15599278, 15599331 |

Figure 11 jobs 15598517, 15598684, 15598690 and 15598705 (320 functions,
31-minute configuration) were cancelled and their logs were not archived.
Their outcomes are known only from notes taken at the time.

### Known problems in the results

- **Wrong outputs.** Torpor returns wrong inference outputs (`0.0`, `nan` or
  large values) at a rate far above the authors' own log (0.11%): 16.5% in the
  40-function Figure 11 probe, 1.4% in Figure 10 at 120 functions, 40.1% at
  160 functions. Figure 10 still reports 100% SLO compliance, because
  resnet152's run time does not depend on the data. The cause is not
  identified.
- **Figure 11 crash.** At 320 functions, memory pressure makes requests
  overlap on one GPU. `active_func_` is a single member per server, so
  overlapping requests are likely translated with the wrong client's memory
  map. With bertqa this becomes an out-of-range embedding index, a device-side
  assert and a crash. This explanation rests on single probe runs. See
  [`diagnostics/`](diagnostics/) for the patches that were tried.
- **Single runs.** Only Figure 9 was run as two independent jobs.

## Layout and setup

```
$TORPOR/
  torpor/     this repository
  images/     Apptainer images (images/README.md)
  models/     offline model caches (TORCH_HOME, HF_HOME)
  venv/       Python venv for the host-side drivers
```

`common/env.sh` derives `TORPOR` from the location of this repository; export
it to override. Setup:

1. Build the six images: [`images/README.md`](images/README.md).
2. Fill `$TORPOR/models` (listed in `images/README.md`).
3. Create the venv. Upstream asks for `zmq numpy protobuf==3.20.1 requests
   pandas`. The runs used Python 3.9 with numpy 2.0.2, pandas 2.3.3,
   protobuf 3.20.1, pyzmq 27.1.0 and requests 2.32.5.
4. Run a figure from its directory:

   ```bash
   cd reproduction/figure10
   mkdir -p logs_batch
   sbatch -A <project> sbatch_figure10.sh
   ```

   The sbatch scripts request a whole JURECA `dc-gpu` node
   (`--gres=gpu:4,mem512:1`). On another cluster, adjust the `#SBATCH` lines
   and `NUMA_CORES` in the routers. The account comes from `-A` or
   `SBATCH_ACCOUNT`. Results are copied to `$HOME/results/<figure>/`
   (override with `RESULTS_ROOT`).

## Directory map

Every directory follows the same pattern: `sbatch_<figure>.sh` submits the
figure, `run_all_<figure>.sh` runs all variants in sequence (and deletes the
previous logs unless `KEEP_LOGS=1`), and `run_<short>_<variant>.sh` runs one
variant interactively on a compute node.

| Directory | Artifact | Variants |
|---|---|---|
| [`table4/`](table4/) | Table 4 | Native, GPU remoting, Swap-PCIe, Swap-NVLink (8 models) |
| [`figure6/`](figure6/) | Figure 6 | Torpor, w/o batch (resnet152, bertqa) |
| [`figure7/`](figure7/) | Figure 7 | Baseline, +Pinned, +Pipeline, +Group (resnet152, bertqa) |
| [`figure8/`](figure8/) | Figure 8 | Native 19 functions at 80/60/40/20/10 rpm; Torpor (33,80) (40,60) (60,40) (120,20) (210,10) |
| [`figure9/`](figure9/) | Figure 9 | Native, Torpor on traces -5, -7, -1, -10 |
| [`figure10/`](figure10/) | Figure 10 | Native, Torpor, INFless-KA at 40/80/120/160 functions |
| [`figure11/`](figure11/) | Figure 11 | Torpor, -FIFO, -Block, -LRU, -Random at 320 to 560 functions; two diagnostic probes |
| [`common/`](common/) | shared | `env.sh`, `model_loop.sh`, `kill_stale.sh`, `ports.sh` |
| [`images/`](images/) | | Apptainer definition files and source patches |
| [`diagnostics/`](diagnostics/) | | Server patches tried for Figure 11; not used for results |

## Deviations from upstream

### Server

The server is measured as published, with one exception: `host_addr` in
`ModelRepo::load_model_h2d_at_start` (`include/server/model_repo.hpp`) is
initialised to 0. Upstream leaves it uninitialised. When the model lookup
misses (which the load-time registration race causes), the unfixed server
copies to a garbage address, which sometimes crashes (SIGSEGV) and sometimes
silently corrupts memory. With the fix, it logs a warning and skips the copy.
So the fix removes a crash path but not the underlying race. Crash rates here
are therefore likely lower than with the unmodified artifact.

All reported results ran on images built with this fix (from 2026-08-09 on).
The unmodified server images were kept, and only jobs before that date used
them.

### Docker to Apptainer

JURECA provides neither root nor a Docker daemon.

| Upstream (Docker) | Here (Apptainer) |
|---|---|
| `docker run --rm` / `docker stop` | Plain host processes, cleaned up with `pkill` before and after every run (`common/kill_stale.sh`) |
| Edit a source file in the running container and `make` (Table 4 NVLink, Fig. 6 w/o batch, Fig. 7 Baseline) | Prebuilt variant images (`images/`) |
| `--network=host --ipc=host` | Default in Apptainer; `/dev/shm/ipc` bound to `/cuda` as before |
| `--cpus=1` | `taskset`: clients pinned to cores local to their GPU (`NUMA_CORES`), router on core 200 |
| `--gpus device=N` | `CUDA_VISIBLE_DEVICES=N` with `apptainer --nv` |
| Client ports `9000 + id` | `20000 + id` (`CLIENT_PORT_BASE`): port 9100 is taken by the node's Prometheus node_exporter, which answered the readiness probe for client 100 and deadlocked the launch |
| Weights downloaded in the container | Offline caches via `TORCH_HOME`, `HF_HOME`, `HF_HUB_OFFLINE=1` (no internet on compute nodes) |

### V100 to A100

- `MEM_LIMIT_IN_GB=25` is kept from the paper's configuration, so the
  per-GPU model capacity, and with it the swapping pressure, matches the paper.
- A100 inference is about 1.13x faster for resnet152 on identical Torpor
  configurations.

### Harness changes that can affect behaviour

| Change | Where | Effect on reported results |
|---|---|---|
| `get_server_id()` returns `client_id % server_num` instead of `% 4` | `baseline_native.py` (Figs. 8 to 10) | Fixes the Fig. 8 Native baseline, which served only 5 of 19 functions with `-s 1`. Identical at `-s 4` |
| After a request timeout a function is retried after 10 s (`UNHEALTHY_COOLDOWN`); upstream drops it for the rest of the run | routers and baselines, Figs. 8 to 11 | Fired in the Fig. 10 Native and INFless-KA runs; effect not measured |
| Clients that die during launch are relaunched; the readiness probe rejects non-JSON answers | routers and baselines, Figs. 8 to 11 | Launch phase only |
| `time.sleep(2)` after each client launch | routers, Figs. 9 to 11 | Launch phase only; lowers the rate of registration failures |
| Trace cache keyed by rate | `figure8/sender_fix_rate.py` | Upstream would replay the first rate's trace for all Native rates |
| Cached trace regenerated if it references functions beyond the current count | `sender_from_trace.py`, Figs. 10 and 11 | None for a clean cache |
| INFless-KA: terminations use `pkill` and their own thread pool; functions waiting for termination are not selected again | `figure10/baseline_keepalive.py` | Not measured |
| SLO deadline 100 ms to 80 ms | `figure10/figure10_analyze_router_log.py` | None: identical table under both |
| Model weights staged to `/dev/shm` | Fig. 11 sbatch scripts | Lowers the rate of the load-time race |
| Fixed 60 s wait replaced by polling for the endpoint; `print(elasped)` removed | Fig. 6 drivers | None |

The analyzers of Figures 8, 9 and 11 are upstream's, unchanged.

### Code state against the runs

- The scripts here are the final state of the harness plus a cleanup for
  publication (comments shortened, cluster paths replaced by `$TORPOR`,
  account removed from `#SBATCH`). The cleanup was checked mechanically:
  apart from the path and environment lines, every Python file is
  token-identical and every shell script parses to identical code.
- On 2026-09-29, after all runs, the three copies of `baseline_native.py`
  (Figs. 8 to 10) were synchronised. For Figures 9 and 10 this changed
  `% 4` to `% server_num` (identical at `-s 4`) and made the log directory
  depend on the current directory (resolves to the same path). The pre-sync
  versions were not kept.

## Provenance of the files

| File(s) here | Upstream origin |
|---|---|
| `table4/{GPU_remoting_latency,swap_PCIe_latency,swap_NVLink_latency}.py` | `evaluation2/table4/`, client launch changed |
| `table4/run_figure4_native.py`, `*/signal_pb2.py` | `evaluation2/table4/`, `evaluation2/figure10/`, unchanged |
| `figure6/fig6_torpor.py` | `evaluation/figure6/test_scripts/torpor.py` |
| `figure6/fig6_nobatch/torpor_without_batch.py` | `evaluation/figure6/test_scripts/torpor_without_batch.py` |
| `figure7/swap_PCIe_latency.py` | `evaluation/figure7/test_scripts/swap_PCIe_latency.py` |
| `figure{8,9,10,11}/router.py` | `evaluation2/figure10/router.py` (identical to the upstream per-figure routers) |
| `figure{8,9,10}/baseline_native.py` | `evaluation2/figure10/baseline_native.py` |
| `figure10/baseline_keepalive.py` | `evaluation2/figure10/baseline_keepalive.py` |
| `figure{8,9}/sender_fix_rate.py` | `evaluation/figure{8,9}/test_scripts/sender_fix_rate.py` |
| `figure10/sender_from_trace.py` | `evaluation2/figure10/sender_from_trace.py` |
| `figure11/sender_from_trace.py` | `evaluation/figure11/test_scripts/sender_from_trace.py` |
| `figure8/figure8_analyze_router_log.py` | `evaluation/figure8/test_scripts/Figure8_analyze_router_log.py`, unchanged |
| `figure9/figure9_analyze_router_log.py`, `figure11/figure11_analyze_router_log.py` | upstream, unchanged |
| `figure10/figure10_analyze_router_log.py` | `evaluation2/figure10/`, deadline changed |
| all `*.sh`, `common/`, `images/`, `diagnostics/` | new |

`git diff` between an upstream file and its copy here shows exactly what the
port changed.

## Data

The raw logs and result files of every job listed above are on Zenodo
(DOI: TODO), organised by artifact, with job IDs and checksums. The authors'
own logs, linked from the upstream figure READMEs, were used for comparison
but are not redistributed.

## History of this branch

The first commit on top of upstream is the `host_addr` fix. The branch
`server-fixes-diagnostics` holds earlier race fixes and extra logging and was
not used for any result. Before publication, both local commits were
re-authored; their original hashes were `962210d` (the `host_addr` fix) and
`2d51080` (the diagnostics).

## License

Upstream is MIT-licensed (Copyright (c) 2025 FCSLab). The additions in this
directory are MIT-licensed as well; see [`../LICENSE`](../LICENSE).
