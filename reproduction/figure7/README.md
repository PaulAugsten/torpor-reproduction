# Figure 7: model swapping optimisations

Four cumulative variants per model (resnet152, bertqa), all driven by
`swap_PCIe_latency.py` (every request forces a host-to-GPU swap). This is
upstream's `evaluation/figure7/test_scripts/swap_PCIe_latency.py` with the
client launched through Apptainer.

| Variant   | Server image                      | Extra server env         |
|-----------|-----------------------------------|--------------------------|
| Baseline  | `torpor-server-fig7-baseline.sif` | `BUFFER_SIZE=1610612736` |
| +Pinned   | `torpor-server.sif`               | `BUFFER_SIZE=1610612736` |
| +Pipeline | `torpor-server.sif`               | `BUFFER_SIZE=1`          |
| +Group    | `torpor-server.sif`               | none (default)           |

The Baseline image has the pinned staging path in `memory_manager.hpp`
commented out, as the upstream Figure 7 README instructs. The exact patch is
`../images/patches/fig7-baseline-memory_manager.patch`. General porting notes
are in [`../README.md`](../README.md).

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_figure7.sh
# or interactively on a compute node, venv active:
./run_all_figure7.sh             # wipes previous logs first (KEEP_LOGS=1 keeps them)
```

## Individual variants

```bash
./run_fig7_baseline.sh
./run_fig7_pinned.sh
./run_fig7_pipeline.sh
./run_fig7_group.sh
```

All four share `../common/model_loop.sh` (fresh server per model, 30-minute
driver timeout, full teardown between models).

Outputs: `results_fig7_<variant>.txt` (summaries), `logs_fig7_<variant>/`
(raw logs per model).
