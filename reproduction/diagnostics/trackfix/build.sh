#!/bin/bash
# Rebuild the server inside torpor-server.sif with an overlay; the patched
# header is expected at /tmp/patched_cuda_server.hpp (see README.md).
set -e
cp /tmp/patched_cuda_server.hpp /gpu-swap/include/server/cuda_server.hpp
cd /gpu-swap/build
make server -j 16
ls -la /gpu-swap/build/target/server
cp /gpu-swap/build/target/server /server_bin/server
echo "INSTALLED-OK"
