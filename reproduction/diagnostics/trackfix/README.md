# `send_complete_signal` tracking-window patch (built, measured, backed out)

## What the patch did

Model registration is bracketed by `set_track_model_memory()` on signal 1 and
`unset_track_model_memory()` inside `send_complete_signal()`. The close only
fires when `load_model_flag_ == LoadModelFlag_TrackAccess`, which is set only
by `cudaDeviceSynchronizeService` (commented `// walkaround` upstream). But
`send_complete_signal()` runs on every device-to-host copy, so a D2H copy that
arrives while a model is still loading takes the `else` branch and drops the
window. Because `track_memory_flag_` is a single `pair<bool,string>` per
server, the next model's open takes it over, and the abandoned model's
parameters are never registered.

The patch added a `LoadModelFlag_LoadModel` branch that keeps `active_func_`
and the window, still pushing to `controller_sync_queue`.

The patched `cuda_server.hpp` was not kept. Only this description and the
build script remain.

## Result: bookkeeping fixed, outputs unchanged

Jobs with 320 functions, 31-minute configuration (their logs were not
archived; numbers from notes taken at the time):

| | stock + GPFS (15598517) | patched + tmpfs (15598690) | stock + tmpfs (15598705) |
|---|---|---|---|
| clobbers per executor | 2/0/4/0 | 0/0/0/0 | 0/0/0/0 |
| `fails to find malloc` | 570 | 0 | 0 |
| `parameter ptr not found` | 11151 | 0 | 0 |
| load phase | **SIGSEGV** | completed | completed |
| warm-up func 5 | -21.933094 (all servers) | -0.0089 / 0 / 0 / 0 | -0.0089 / 0 / 0 / 0 |
| warm-up func 6 | 15.983399 (all servers) | -9.4e10 / -2.25e11 / -1.07e11 / -2.25e11 | identical to patched |

Functions 1, 3, 4, 5 and 6 are bit-identical between the patched and the stock
tmpfs run, so the patch does not change computed outputs. It only cleans up
the registration bookkeeping, which tmpfs staging alone already achieves.
The patch was therefore backed out.

Comparing the patched run with stock + GPFS would change two things at once;
the stock + tmpfs control isolates the patch.

## Rebuilding

The server image contains the full source in `/gpu-swap` and a configured
build tree, so only `server.cpp` recompiles:

```bash
apptainer overlay create --size 6144 overlay.img
apptainer exec --overlay overlay.img \
  --bind <patched cuda_server.hpp>:/tmp/patched_cuda_server.hpp:ro \
  "$TORPOR/images/torpor-server.sif" bash /path/to/build.sh
```

`build.sh` copies the patched header into place, runs `make server` and
installs the binary into the overlay's `/server_bin/server`.
