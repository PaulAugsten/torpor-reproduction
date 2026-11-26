# Torpor reproduction on JURECA (Apptainer, 4x A100)

This directory contains a reproduction of the single-node evaluation of the
Torpor paper (M. Yu et al., "Torpor: GPU-Enabled Serverless Computing for Low-Latency, Resource-Efficient Inference", USENIX ATC 2025)
using the authors' artifact
([s4-lab-cuhksz/torpor](https://github.com/s4-lab-cuhksz/torpor)). The
upstream evaluation is a set of Docker commands for a 4x V100 cloud VM. Here
it is ported to Apptainer and Slurm and run on one JURECA DC-GPU node at the
Jülich Supercomputing Centre (4x NVIDIA A100-40GB, 2x AMD EPYC 7742).

- Authors: Paul Augsten (University of Cologne), Laurin Remane (University of Cologne; Figure 11)
- Raw logs and result files: Zenodo, DOI: [10.5281/zenodo.24373400](https://doi.org/10.5281/zenodo.24373400)

The upstream artifact contains only the single-node prototype, so the
reproducible scope is Table 4 and Figures 6 to 11 (paper Sections 7.1 to 7.3).

<!---The results are discussed in the accompanying report (TODO: citation). --->

Absolute latencies differ from the paper (different GPUs). What can be
compared are the relations between bars and the trends.

Everything outside `reproduction/` is code from the original repo, except for two one-line
server fixes (see [Server](#server)).

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
    and the core lists (`NUMA_CORES` in the routers and baselines, the
    `taskset` cores in the run scripts). The account comes from `-A` or
    `SBATCH_ACCOUNT`. Results are copied to `$HOME/results/<figure>/`
    (override with `RESULTS_ROOT`).

## Directory map

Every directory follows the same pattern: `sbatch_<figure>.sh` submits the
figure, `run_all_<figure>.sh` runs all variants in sequence (and deletes the
previous logs unless `KEEP_LOGS=1`), and `run_<short>_<variant>.sh` runs one
variant interactively on a compute node.

| Directory                | Artifact  | Variants                                                                                    |
| ------------------------ | --------- | ------------------------------------------------------------------------------------------- |
| [`table4/`](table4/)     | Table 4   | Native, GPU remoting, Swap-PCIe, Swap-NVLink (8 models)                                     |
| [`figure6/`](figure6/)   | Figure 6  | Torpor, w/o batch (resnet152, bertqa)                                                       |
| [`figure7/`](figure7/)   | Figure 7  | Baseline, +Pinned, +Pipeline, +Group (resnet152, bertqa)                                    |
| [`figure8/`](figure8/)   | Figure 8  | Native 19 functions at 80/60/40/20/10 rpm; Torpor (33,80) (40,60) (60,40) (120,20) (210,10) |
| [`figure9/`](figure9/)   | Figure 9  | Native, Torpor on traces -5, -7, -1, -10                                                    |
| [`figure10/`](figure10/) | Figure 10 | Native, Torpor, INFless-KA at 40/80/120/160 functions                                       |
| [`figure11/`](figure11/) | Figure 11 | Torpor, -FIFO, -Block, -LRU, -Random at 320 to 560 functions                                |
| [`common/`](common/)     | shared    | `env.sh`, `model_loop.sh`, `kill_stale.sh`, `ports.sh`                                      |
| [`images/`](images/)     |           | Apptainer definition files and source patches                                               |

## Deviations from the original

### Server

The server carries two one-line fixes.

- **`host_addr`** in `ModelRepo::load_model_h2d_at_start`
  (`include/server/model_repo.hpp`) is initialised to 0. The original leaves it
  uninitialised. When the model lookup misses during loading, the unfixed
  server copies to a garbage address, which sometimes crashes and
  sometimes silently corrupts memory. With the fix, it logs a warning and
  skips the copy. This removes a crash path, so crash rates here are likely
  lower than with the unmodified artifact.
- **`valid_memory_address`** (`include/server/memory_manager.hpp`) returns the
  result of its lookup. In the original there was a missing return statement and therefore false was always returned, so kernel arguments that point inside a model block are never translated and a
  model computes correctly only on the GPU and at the address it was loaded
  at. The same line is fixed in the Figure 7 reference copy
  `evaluation/figure7/test_scripts/memory_manager.hpp`.

### Docker to Apptainer

JURECA provides neither root nor a Docker daemon.

| Upstream (Docker)                                                                                          | Here (Apptainer)                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker run --rm` / `docker stop`                                                                          | Plain host processes, cleaned up with `pkill` before and after every run (`common/kill_stale.sh`)                                                                         |
| Edit a source file in the running container and `make` (Table 4 NVLink, Fig. 6 w/o batch, Fig. 7 Baseline) | Prebuilt variant images (`images/`)                                                                                                                                       |
| `--network=host --ipc=host`                                                                                | Default in Apptainer; `/dev/shm/ipc` bound to `/cuda` as before                                                                                                           |
| `--cpus=1`                                                                                                 | `taskset`: clients pinned to cores local to their GPU (`NUMA_CORES`), router on cores outside those ranges                                                                |
| `--gpus device=N`                                                                                          | `CUDA_VISIBLE_DEVICES=N` with `apptainer --nv`                                                                                                                            |
| Client ports `9000 + id`                                                                                   | `20000 + id` (`CLIENT_PORT_BASE`): port 9100 is taken by the node's Prometheus node_exporter, which answered the readiness probe for client 100 and deadlocked the launch |
| Weights downloaded in the container                                                                        | Offline caches via `TORCH_HOME`, `HF_HOME`, `HF_HUB_OFFLINE=1` (no internet on compute nodes)                                                                             |

### V100 to A100

- `MEM_LIMIT_IN_GB=25` is kept from the paper's configuration, so the
  per-GPU model capacity, and with it the swapping pressure, matches the paper.
- A100 inference is about 1.13x faster for resnet152 on identical Torpor
  configurations, but this heavily depends on the model.

### Harness changes that can affect behaviour

| Change                                                                                                                                     | Where                                     | Effect on reported results                                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `get_server_id()` returns `client_id % server_num` instead of `% 4`                                                                        | `baseline_native.py` (Figs. 8 to 10)      | Fixes the Fig. 8 Native baseline, which served only 5 of 19 functions with `-s 1`. Identical at `-s 4` |
| After a request timeout a function is retried after 10 s (`UNHEALTHY_COOLDOWN`); upstream drops it for the rest of the run                 | routers and baselines, Figs. 8 to 10      | Fired in the Fig. 10 Native and INFless-KA runs; effect not measured                                   |
| Clients that die during launch are relaunched; the readiness probe rejects non-JSON answers                                                | routers and baselines, Figs. 8 to 10      | Launch phase only                                                                                      |
| `time.sleep(2)` after each client launch                                                                                                   | routers, Figs. 9 and 10                   | Launch phase only; lowers the rate of model-registration failures                                      |
| Client loads serialized across the 4 GPU managers (file lock); load timeout 120 s instead of 5 s; port polling instead of a fixed 8 s wait | `figure11/router.py`                      | Launch phase only; see [`figure11/README.md`](figure11/README.md)                                      |
| Trace cache keyed by rate                                                                                                                  | `figure8/sender_fix_rate.py`              | Upstream would replay the first rate's trace for all Native rates                                      |
| Cached trace regenerated if it references functions beyond the current count                                                               | `figure10/sender_from_trace.py`           | None for a clean cache                                                                                 |
| INFless-KA: terminations use `pkill` and their own thread pool; functions waiting for termination are not selected again                   | `figure10/baseline_keepalive.py`          | Not measured                                                                                           |
| SLO deadline 100 ms to 80 ms                                                                                                               | `figure10/figure10_analyze_router_log.py` | None: identical table under both                                                                       |
| Model weights staged to `/dev/shm`                                                                                                         | `figure11/sbatch_figure11.sh`             | Faster client loads                                                                                    |
| Fixed 60 s wait replaced by polling for the endpoint; `print(elasped)` removed                                                             | Fig. 6 drivers                            | None                                                                                                   |

The analyzers of Figures 8, 9 and 11 are upstream's, unchanged.

## Data

The raw logs and result files of the reported runs are on Zenodo
([10.5281/zenodo.24373400](https://doi.org/10.5281/zenodo.24373400)), organised by artifact. The authors' own logs, linked from the original figure READMEs, were used for comparison but are not redistributed.

## License

Torpor is MIT-licensed (Copyright (c) 2025 FCSLab). The additions in this
directory are MIT-licensed as well; see [`../LICENSE`](../LICENSE).
