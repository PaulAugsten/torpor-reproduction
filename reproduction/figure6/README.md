# Figure 6: GPU remoting with and without CUDA-call batching

Two bars per model (resnet152, bertqa), as in upstream's
`evaluation/figure6/Figure6_README.md`: Torpor (batching enabled) and
Torpor w/o batch. The paper's figure has a third, GVirtuS-based bar; its code
is not part of the upstream artifact, so it is not reproduced here. General
porting notes are in [`../README.md`](../README.md).

## Run everything

```bash
mkdir -p logs_batch && sbatch -A <project> sbatch_figure6.sh
# or interactively on a compute node, venv active:
./run_all_figure6.sh             # wipes previous logs first (KEEP_LOGS=1 keeps them)
```

## Individual bars

```bash
./run_fig6_torpor.sh             # Torpor: torpor-server.sif, driver fig6_torpor.py
./run_fig6_nobatch.sh            # w/o batch: driver runs inside torpor-client-nobatch.sif
```

`fig6_torpor.py` is upstream's `evaluation/figure6/test_scripts/torpor.py`
with the client launched through Apptainer. For the w/o-batch bar,
`fig6_nobatch/torpor_without_batch.py` (upstream's
`evaluation/figure6/test_scripts/torpor_without_batch.py`) runs inside the
client image with `fig6_nobatch/` as its working directory. It uses the
`signal_pb2.py` in that directory, which was generated with the image's own
`protoc`. The port replaced upstream's fixed 60 s wait for the endpoint with
a polling loop.

Outputs: `results_fig6_torpor.txt`, `results_fig6_nobatch.txt` (summaries),
`logs_fig6_*/` (raw logs per model).
