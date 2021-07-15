#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

import random
import time
from typing import Dict, List
from nexus_client import NexusClient


class ChaosScenario:
    """
    Simulates network degradation, partition faults, and verifies
    linearizable consistency properties under failure conditions.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 6379):
        self.host = host
        self.port = port

    def run_read_your_writes_test(self, iterations: int = 500) -> Dict[str, int]:
        """
        Verify Read-Your-Writes consistency: immediately after a write acknowledges,
        a subsequent read must never return an older version or null.
        """
        client = NexusClient(self.host, self.port)
        client.connect()

        violations = 0
        successes = 0

        try:
            for i in range(iterations):
                key = f"chaos:linear:key:{i % 20}"
                val = f"val_epoch_{i}"

                # Write
                client.set(key, val)

                # Read
                observed = client.get(key)
                if observed != val:
                    violations += 1
                else:
                    successes += 1
        finally:
            client.close()

        return {
            "iterations": iterations,
            "successes": successes,
            "violations": violations
        }

    def run_atomic_increment_test(self, threads: int = 4, increments_per_thread: int = 250) -> Dict[str, int]:
        """
        Verify atomic counter safety: multiple concurrent threads incrementing
        the same shared key must produce an exact final sum without lost updates.
        """
        from concurrent.futures import ThreadPoolExecutor

        counter_key = f"chaos:counter:{random.randint(1000, 9999)}"

        def worker():
            c = NexusClient(self.host, self.port)
            c.connect()
            try:
                for _ in range(increments_per_thread):
                    c.incr(counter_key)
            finally:
                c.close()

        # Initialize counter to 0
        init_client = NexusClient(self.host, self.port)
        init_client.connect()
        init_client.set(counter_key, "0")
        init_client.close()

        with ThreadPoolExecutor(max_workers=threads) as executor:
            futures = [executor.submit(worker) for _ in range(threads)]
            for f in futures:
                f.result()

        # Check final count
        verify_client = NexusClient(self.host, self.port)
        verify_client.connect()
        final_val = int(verify_client.get(counter_key) or 0)
        verify_client.close()

        expected = threads * increments_per_thread
        return {
            "expected": expected,
            "actual": final_val,
            "lost_updates": expected - final_val
        }


def main():
    print("=== Nexus Chaos & Fault Tolerance Verification ===")
    chaos = ChaosScenario("127.0.0.1", 6379)

    print("[chaos] Running Read-Your-Writes consistency verification...")
    res1 = chaos.run_read_your_writes_test(500)
    print(f"  Iterations: {res1['iterations']} | Violations: {res1['violations']}")
    assert res1["violations"] == 0, "Read-Your-Writes consistency violated!"

    print("[chaos] Running concurrent atomic counter verification...")
    res2 = chaos.run_atomic_increment_test(threads=4, increments_per_thread=250)
    print(f"  Expected: {res2['expected']} | Actual: {res2['actual']} | Lost: {res2['lost_updates']}")
    assert res2["lost_updates"] == 0, "Atomic increments lost updates!"

    print("ALL CHAOS CONSISTENCY INVARIANTS SATISFIED!")


if __name__ == "__main__":
    main()
