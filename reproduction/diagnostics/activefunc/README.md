# Per-client `active_func_` patch (FAILED, do not use)

`activefunc.patch` applies to `include/server/cuda_server.hpp` of the
reproduction branch (upstream plus the `host_addr` fix; that file is unchanged
from upstream):

```bash
git apply reproduction/diagnostics/activefunc/activefunc.patch
```

## Motivation

In probe 15599278 (320 functions, 5-minute replay, stock server, tmpfs
staging) the server crashed with a device-side assert
(`indexSelectLargeIndex`). The only functions whose parameters were never
registered were 4 (densenet201) and 233 (resnet101), and every
`parameter ptr not found` in the run belongs to those two. No bertqa function
was unregistered, yet six bertqa requests were in flight when the assert
fired. So a cleanly registered bertqa model read out-of-range token ids,
which the load-time registration race cannot explain.

`active_func_`, `load_model_flag_` and `req_start_` are single members of the
server object, shared by every client on that GPU. `active_func_` is set on
`ExecutorSignal_Execute` from the control queue, while CUDA calls arrive on a
separate socket together with a `client_id`. If client B's Execute arrives
while client A's kernel launches are still coming in, A's remaining launches
are translated with B's memory map.

## What the patch does

It moves those three fields into a per-client record keyed by the `client_id`
that all 52 service methods already receive:

```cpp
struct ClientState {
    string func_ = non_active_func;
    int load_model_flag_ = LoadModelFlag_None;
    std::chrono::time_point<std::chrono::system_clock> req_start_ = ...;
};
std::unordered_map<int, ClientState> client_state_;
```

Both entry points agree on the key, because `func` in an executor signal is
the client id as a string (upstream uses `get_client_addr(stoi(func))`).
`send_complete_signal()` now takes a `client_id`, and the timeout check sweeps
all in-flight clients, rate-limited to once per 200 ms.

`MemoryManager::track_memory_flag_` (the load-time registration window) is
deliberately left per-server, to change one variable at a time.

## Result

Probe 15599331 (320 functions, 5 minutes, this patch): **81 models
unregistered** against 2 for stock, 50881 `parameter ptr not found` against
1526, and the server stopped with `Error: no free physical block`
(`block_manager.hpp:350`, `exit(1)`) during warm-up. Zero requests were
served.

**Splitting the two was the mistake.** With `track_memory_flag_` per-server
but open and close per-client, the two get out of step. The Track/Untrack
sequence shows it. Stock is cleanly nested:

```
Track 40 / Untrack 40 / Track 44 / Untrack 44 / ...
```

The patched server is shifted by one:

```
Track 81 / Untrack 75 / Track 84 / Untrack 81 / Track 88 / Untrack 84 / ...
```

Upstream's global `load_model_flag_` makes the close fire on whatever activity
is current, which keeps the window aligned with the load in progress.
Per-client, model N's close fires only on client N's own D2H copy, which
arrives after the router has launched N+1 and the server has opened N+1's
window. Each late close then clears the next model's slot. Unregistered models
stay `ModelStatus_Incomplete`, their blocks are never reclaimed, and the block
manager runs out.

A correct fix would have to make `track_memory_flag_` per-client in the same
change: a map keyed by client, `unset_track_model_memory` clearing only that
client's entry, and `try_insert_model_access(dev_ptr)` taking a client
argument.

**Detector warning:** `unset_track_model_memory` logs `Untrack memory for
{func}` unconditionally, outside the `if (track_memory_flag_.first)` that
guards `complete_model_load`. A model can log a clean Track/Untrack pair and
still never be registered. In this run the clobber count said 1; the truth was
81. Count `parameter ptr not found` markers instead.

## Rebuilding

From the repository root:

```bash
git apply reproduction/diagnostics/activefunc/activefunc.patch
apptainer overlay create --size 6144 overlay.img
apptainer exec --overlay overlay.img \
  --bind "$PWD/include/server/cuda_server.hpp:/tmp/patched_cuda_server.hpp:ro" \
  --bind "$PWD:/out" "$TORPOR/images/torpor-server.sif" bash -c '
    cp /tmp/patched_cuda_server.hpp /gpu-swap/include/server/cuda_server.hpp
    cd /gpu-swap/build && make server -j 16
    cp target/server /out/server-activefunc'
git checkout include/server/cuda_server.hpp
```

Then run a probe with `SERVER_BIN=$PWD/server-activefunc`.
