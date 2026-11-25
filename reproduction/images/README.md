# Apptainer images

The experiments use six images, expected in `$TORPOR/images/`:

| Image                             | Contents                                                | Used by                                                                                |
| --------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `torpor-server.sif`               | server + `host_addr` and `valid_memory_address` fixes   | Table 4 remoting/Swap-PCIe, Fig. 6, Fig. 7 (+Pinned, +Pipeline, +Group), Figs. 8 to 11 |
| `torpor-server-nvlink.sif`        | as above + `evaluation2/table4/controller.hpp`          | Table 4 Swap-NVLink                                                                    |
| `torpor-server-fig7-baseline.sif` | as above + `patches/fig7-baseline-memory_manager.patch` | Fig. 7 Baseline                                                                        |
| `torpor-client.sif`               | client                                                  | all Torpor runs                                                                        |
| `torpor-client-nobatch.sif`       | client + `patches/client-nobatch-async_sender.patch`    | Fig. 6 w/o batch                                                                       |
| `torpor-native.sif`               | native image                                            | Table 4 Native, Native baselines of Figs. 8 to 10, INFless-KA                          |

The server images carry two one-line fixes on top of the original repo at commit `1484e74`:

| Fix                                              | File                                | Without it                                                                                                                                                                                     |
| ------------------------------------------------ | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `host_addr = 0` in `load_model_h2d_at_start`     | `include/server/model_repo.hpp`     | a failed lookup during model loading copies to an uninitialised address (SIGSEGV or silent corruption)                                                                                         |
| `valid_memory_address` returns the lookup result | `include/server/memory_manager.hpp` | kernel arguments pointing inside a model block are never translated, so a model computes correctly only on the GPU and at the address it was loaded at (wrong outputs, bert-qa device asserts) |

## Images used for Table 4 and Figures 6 to 11

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

These images were not built from the `.def` files. Their sources
(`/gpu-swap/include`, `/gpu-swap/src`) were extracted and compared file by file
with the repository:

| Image                                                                  | Sources are identical to                                |
| ---------------------------------------------------------------------- | ------------------------------------------------------- |
| `torpor-server-pristine.sif`, `torpor-client.sif`, `torpor-native.sif` | original commit `1484e74`                               |
| `torpor-server.sif`                                                    | `1484e74` + `host_addr` fix                             |
| `torpor-server-nvlink.sif`                                             | + `evaluation2/table4/controller.hpp`                   |
| `torpor-server-fig7-baseline.sif`                                      | + `patches/fig7-baseline-memory_manager.patch`          |
| `torpor-client-nobatch.sif`                                            | `1484e74` + `patches/client-nobatch-async_sender.patch` |

## Building from the definition files

The `.def` files script step 3. For
`torpor-server-fig7-baseline`, the Figure 7 patch is applied on top of the
fixed file.

Build from the repository root, because the `%files` paths are relative to it:

```bash
cd <repo>
for img in torpor-server torpor-server-nvlink torpor-server-fig7-baseline \
           torpor-client torpor-client-nobatch torpor-native; do
    apptainer build "$TORPOR/images/$img.sif" "reproduction/images/$img.def"
done
```

The images are 7 to 10 GB each.

## Model weights

Compute nodes have no internet access. The clients read the model weights from
`$TORPOR/models/torch` and `$TORPOR/models/hf`, which must be filled once on a
machine with internet access. The runs used these caches (about 2 GB):

- `torch/hub/checkpoints/`: the torchvision weights `densenet169-b2777c0a.pth`,
  `densenet201-c1103571.pth`, `efficientnet_b0_rwightman-3dd342df.pth`,
  `inception_v3_google-0cc3c7bd.pth`, `resnet50-0676ba61.pth`,
  `resnet101-63fe2227.pth`, `resnet152-394f9c45.pth`
- `hf/hub/models--bert-large-uncased-whole-word-masking-finetuned-squad/`
  (Hugging Face hub cache layout)
