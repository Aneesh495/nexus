#!/usr/bin/env bash
#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#
set -euo pipefail

echo "================================================================="
echo "   Launching Nexus 3-Node Distributed Cluster"
echo "================================================================="

PIDS=()

cleanup() {
    echo ""
    echo "[cluster] Shutting down cluster nodes..."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    echo "[cluster] All nodes stopped."
}

trap cleanup EXIT INT TERM

# Start Node 1 (port 6379)
echo "[cluster] Starting Node 1 on port 6379..."
fan nexus::NexusServerMain -p 6379 &
PIDS+=($!)
sleep 1

# Start Node 2 (port 6380)
echo "[cluster] Starting Node 2 on port 6380..."
fan nexus::NexusServerMain -p 6380 &
PIDS+=($!)
sleep 1

# Start Node 3 (port 6381)
echo "[cluster] Starting Node 3 on port 6381..."
fan nexus::NexusServerMain -p 6381 &
PIDS+=($!)
sleep 1

echo "================================================================="
echo "   Cluster Online: 3 Active Nodes"
echo "   - Node 1: redis://127.0.0.1:6379 (http://127.0.0.1:6379/)"
echo "   - Node 2: redis://127.0.0.1:6380 (http://127.0.0.1:6380/)"
echo "   - Node 3: redis://127.0.0.1:6381 (http://127.0.0.1:6381/)"
echo "================================================================="
echo "Press Ctrl+C to terminate cluster."

wait
