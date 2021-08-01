#!/usr/bin/env bash
#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#
set -euo pipefail

echo "================================================================="
echo "   Running Nexus In-Process & Multi-Threaded Benchmarks"
echo "================================================================="

echo ""
echo "[bench] 1. In-process Fantom load test (50,000 operations)..."
fan nexus::NexusBenchmark -n 50000

echo ""
echo "[bench] 2. Native C acceleration test..."
(cd native && make test)

echo ""
echo "[bench] 3. Python YCSB benchmark test suite..."
pytest tests/

echo ""
echo "================================================================="
echo "   All Benchmarks and Verification Runs Completed Successfully!"
echo "================================================================="
