# Apptainer images

The experiments use six images, expected in `$TORPOR/images/`:

| Image | Contents | Used by |
|---|---|---|
| `torpor-server.sif` | upstream server + `host_addr` fix | Table 4 remoting/Swap-PCIe, Fig. 6, Fig. 7 (+Pinned, +Pipeline, +Group), Figs. 8 to 11 |
| `torpor-server-nvlink.sif` | as above + upstream's `evaluation2/table4/controller.hpp` | Table 4 Swap-NVLink |
| `torpor-server-fig7-baseline.sif` | as above + `patches/fig7-baseline-memory_manager.patch` | Fig. 7 Baseline |
| `torpor-client.sif` | upstream client | all Torpor runs |
| `torpor-client-nobatch.sif` | upstream client + `patches/client-nobatch-async_sender.patch` | Fig. 6 w/o batch |
| `torpor-native.sif` | upstream native image | Table 4 Native, Native baselines of Figs. 8 to 10, INFless-KA |

The `host_addr` fix is the one-line change to `include/server/model_repo.hpp`
in the commit directly on top of upstream `1484e74` on this branch. It is the
only change to the server in all reported results; see
[`../README.md`](../README.md).

## How the original images were built

1. The Docker images `standalone-server`, `standalone-client` and
   `standalone-native` were built from upstream commit `1484e74` with the
   upstream `dockerfiles/`, as described in the upstream README, and pushed as
   `paulaugsten/torpor:{server,client,native}` (the digests are in the `.def`
   files).
2. On JURECA they were converted with `apptainer build <name>.sif docker://...`.
   The converted server image is kept as `torpor-server-pristine.sif`.
3. The variant images were built interactively: sandbox, copy the modified
   header into `/gpu-swap`, `make` in `/gpu-swap/build`, copy the binary into
   place, `apptainer build` the SIF.

## Definition files

The `.def` files in this directory were written afterwards to document step 3
reproducibly. **They were not used to build the original images, and building
from them has not been tested.** What was checked is that they describe the
same source changes as the original images. The sources in each original SIF
(`/gpu-swap/include`, `/gpu-swap/src`) were extracted and compared file by
file with the repository:

| Original image | Sources are identical to |
|---|---|
| `torpor-server-pristine.sif`, `torpor-client.sif`, `torpor-native.sif` | upstream `1484e74` |
| `torpor-server.sif` | `1484e74` + `host_addr` fix |
| `torpor-server-nvlink.sif` | + `evaluation2/table4/controller.hpp` (byte-identical) |
| `torpor-server-fig7-baseline.sif` | + `patches/fig7-baseline-memory_manager.patch` |
| `torpor-client-nobatch.sif` | `1484e74` + `patches/client-nobatch-async_sender.patch` |

The rebuilt binaries in every variant image carry the same timestamp as the
modified header, which is consistent with the procedure above.

Build from the repository root, because the `%files` paths are relative to it:

```bash
cd <repo>
for img in torpor-server torpor-server-nvlink torpor-server-fig7-baseline \
           torpor-client torpor-client-nobatch torpor-native; do
    apptainer build "$TORPOR/images/$img.sif" "reproduction/images/$img.def"
done
```

The server `.def` files copy `include/server/model_repo.hpp` from the working
tree, so check out the commit with the `host_addr` fix (or later) before
building.

The images are 7 to 10 GB each and contain NVIDIA's `pytorch:22.01-py3` base
image, so they are not redistributed with this repository or the data record.

## Model weights

Compute nodes have no internet access. The clients read the model weights from
`$TORPOR/models/torch` (`TORCH_HOME`) and `$TORPOR/models/hf` (`HF_HOME`, with
`HF_HUB_OFFLINE=1`), which must be filled once on a machine with internet
access. The runs used these caches (about 2 GB):

- `torch/hub/checkpoints/`: the torchvision weights `densenet169-b2777c0a.pth`,
  `densenet201-c1103571.pth`, `efficientnet_b0_rwightman-3dd342df.pth`,
  `inception_v3_google-0cc3c7bd.pth`, `resnet50-0676ba61.pth`,
  `resnet101-63fe2227.pth`, `resnet152-394f9c45.pth`
- `hf/hub/models--bert-large-uncased-whole-word-masking-finetuned-squad/`
  (Hugging Face hub cache layout)
