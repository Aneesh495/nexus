#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

import argparse
import random
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Tuple
from nexus_client import NexusClient


class YcsbWorkload:
    """
    Standard YCSB benchmark workload generator.
    Supports Workload A (50/50), B (95/5), and C (100% read).
    """

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 6379,
        keyspace_size: int = 10000,
        workload_type: str = "A",
        value_size_bytes: int = 128
    ):
        self.host = host
        self.port = port
        self.keyspace_size = keyspace_size
        self.workload_type = workload_type.upper()
        self.payload = "x" * value_size_bytes

    def preload(self, count: int = 1000) -> None:
        """Preload initial keyspace before running benchmark."""
        client = NexusClient(self.host, self.port)
        client.connect()
        try:
            for i in range(count):
                client.set(f"user:{i}", self.payload)
        finally:
            client.close()

    def run_worker(self, operations_per_worker: int) -> List[float]:
        """Execute workload operations on a dedicated client connection."""
        client = NexusClient(self.host, self.port)
        client.connect()
        latencies = []
        rng = random.Random()

        try:
            for _ in range(operations_per_worker):
                key = f"user:{rng.randint(0, self.keyspace_size - 1)}"
                roll = rng.random()

                t0 = time.perf_counter()

                if self.workload_type == "A":
                    # 50% reads, 50% updates
                    if roll < 0.50:
                        client.get(key)
                    else:
                        client.set(key, self.payload)
                elif self.workload_type == "B":
                    # 95% reads, 5% updates
                    if roll < 0.95:
                        client.get(key)
                    else:
                        client.set(key, self.payload)
                elif self.workload_type == "C":
                    # 100% reads
                    client.get(key)
                else:
                    # Default: read
                    client.get(key)

                t1 = time.perf_counter()
                latencies.append((t1 - t0) * 1000.0)  # Convert to ms
        finally:
            client.close()

        return latencies


def run_benchmark(
    host: str = "127.0.0.1",
    port: int = 6379,
    threads: int = 4,
    total_ops: int = 10000,
    workload: str = "A"
) -> Dict[str, float]:
    """Execute concurrent YCSB load generation across worker threads."""
    ops_per_thread = total_ops // threads
    generator = YcsbWorkload(host, port, keyspace_size=10000, workload_type=workload)

    # Preload initial working set
    generator.preload(count=min(1000, total_ops // 2))

    t_start = time.perf_counter()

    with ThreadPoolExecutor(max_workers=threads) as executor:
        futures = [executor.submit(generator.run_worker, ops_per_thread) for _ in range(threads)]
        all_latencies = []
        for f in futures:
            all_latencies.extend(f.result())

    t_end = time.perf_counter()
    duration = max(t_end - t_start, 0.001)

    all_latencies.sort()
    count = len(all_latencies)

    p50 = all_latencies[int(count * 0.50)]
    p95 = all_latencies[int(count * 0.95)]
    p99 = all_latencies[int(count * 0.99)]
    p999 = all_latencies[int(count * 0.999)]

    throughput = count / duration

    return {
        "workload": workload,
        "threads": threads,
        "total_ops": count,
        "duration_sec": duration,
        "ops_per_sec": throughput,
        "p50_ms": p50,
        "p95_ms": p95,
        "p99_ms": p99,
        "p999_ms": p999
    }


def main():
    parser = argparse.ArgumentParser(description="Nexus YCSB Workload Generator")
    parser.add_argument("--host", default="127.0.0.1", help="Cluster node host")
    parser.add_argument("-p", "--port", type=int, default=6379, help="Cluster node port")
    parser.add_argument("-t", "--threads", type=int, default=4, help="Concurrent client threads")
    parser.add_argument("-n", "--ops", type=int, default=5000, help="Total operations")
    parser.add_argument("-w", "--workload", default="A", choices=["A", "B", "C"], help="YCSB workload")

    args = parser.parse_args()

    print(f"=== Nexus YCSB Benchmark [Workload {args.workload}] ===")
    print(f"Target: {args.host}:{args.port} | Threads: {args.threads} | Operations: {args.ops}")

    results = run_benchmark(
        host=args.host,
        port=args.port,
        threads=args.threads,
        total_ops=args.ops,
        workload=args.workload
    )

    print("\n--------------------------------------------------------------")
    print(f"  Throughput:    {results['ops_per_sec']:,.0f} ops/sec")
    print(f"  Total Time:    {results['duration_sec']:.2f} seconds")
    print(f"  p50 Latency:   {results['p50_ms']:.3f} ms")
    print(f"  p95 Latency:   {results['p95_ms']:.3f} ms")
    print(f"  p99 Latency:   {results['p99_ms']:.3f} ms")
    print(f"  p99.9 Latency: {results['p999_ms']:.3f} ms")
    print("--------------------------------------------------------------")


if __name__ == "__main__":
    main()
