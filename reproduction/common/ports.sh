#!/bin/bash
# Client endpoint port base for the router-based experiments (Figures 8-11).
# Must match CLIENT_PORT_BASE in router.py / baseline_native.py /
# baseline_keepalive.py. Upstream uses 9000, which puts client 100 on port
# 9100, taken by the node's Prometheus node_exporter on JURECA.
CLIENT_PORT_BASE=${CLIENT_PORT_BASE:-20000}
export CLIENT_PORT_BASE
