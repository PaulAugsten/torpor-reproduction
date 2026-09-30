# Table 4: latency with GPU remoting and model swapping

All four columns run the same 8 models (densenet169/201, inception,
efficientnet, resnet50/101/152, bertqa) and print a per-model
`Latency avg` / `End2End avg` summary. General porting notes are in
[`../README.md`](../README.md).

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_table4.sh
# or interactively on a compute node, venv active:
./run_all_table4.sh              # wipes previous logs first (KEEP_LOGS=1 keeps them)
```

## Individual columns

```bash
./run_table4_native.sh           # Native        (torpor-native.sif, no server)
./run_table4_remoting.sh         # GPU remoting  (torpor-server.sif)
./run_table4_swap_pcie.sh        # Swap-PCIe     (torpor-server.sif)
./run_table4_swap_nvlink.sh      # Swap-NVLink   (torpor-server-nvlink.sif)
```

The remoting and swap columns share `../common/model_loop.sh`: for each model
it starts a fresh server, waits for all 4 GPU executors, runs the driver
(`GPU_remoting_latency.py`, `swap_PCIe_latency.py`, `swap_NVLink_latency.py`)
under a 30-minute timeout, records the result and tears everything down.

Outputs: `results_<column>.txt` (summary) and `logs_<column>/` (server,
client and driver logs per model).

## Relation to upstream

The three drivers are upstream's `evaluation2/table4/*.py` with the
`docker run` client launch replaced by `apptainer exec`.
`run_figure4_native.py` is copied unchanged. Upstream builds the Swap-NVLink
server by copying `evaluation2/table4/controller.hpp` into the container and
recompiling; here that happens once when the image is built
(`../images/torpor-server-nvlink.def`).
