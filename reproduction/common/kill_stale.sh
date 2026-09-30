#!/bin/bash
# Process cleanup for the router-based experiments (Figures 8-11).
# Apptainer has no daemon that tracks containers, so the server, router and
# client endpoints are killed by command-line pattern. The list covers every
# variant, so calling it before a run also removes leftovers of a crashed run.

kill_stale_processes() {
    pkill -f baseline_native.py 2>/dev/null
    pkill -f baseline_keepalive.py 2>/dev/null
    pkill -f 'router.py' 2>/dev/null
    pkill -f start_with_server_id 2>/dev/null
    pkill -f 'endpoint.py 2' 2>/dev/null
    pkill -f '/server_bin/server' 2>/dev/null
    sleep 2
    # A process still in CUDA teardown would otherwise compete for CPU and GPU
    # with the next run and inflate its measured latency.
    pkill -KILL -f baseline_native.py 2>/dev/null
    pkill -KILL -f baseline_keepalive.py 2>/dev/null
    pkill -KILL -f 'router.py' 2>/dev/null
    pkill -KILL -f start_with_server_id 2>/dev/null
    pkill -KILL -f 'endpoint.py 2' 2>/dev/null
    pkill -KILL -f '/server_bin/server' 2>/dev/null
    sleep 1
}
