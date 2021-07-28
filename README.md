# Nexus
### Distributed In-Memory Data Grid & Reactive State Fabric

```
   _   _  _______  __ _   _ ____  
  | \ | || ____\ \/ /| | | / ___| 
  |  \| ||  _|   \  / | | | \___ \ 
  | |\  || |___  /  \ | |_| |___) |
  |_| \_||_____|/_/\_\ \___/|____/ 
```

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Fantom](https://img.shields.io/badge/fantom-1.0.84-blue.svg)]()
[![Language](https://img.shields.io/badge/language-Fantom%20%7C%20C%20%7C%20Python-orange.svg)]()
[![Protocol](https://img.shields.io/badge/protocol-RESP3%20%7C%20Binary%20RPC%20%7C%20HTTP-purple.svg)]()
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Nexus is an ultra-low-latency, partition-tolerant distributed in-memory data grid (IMDG) and reactive state fabric built from scratch. It unifies actor-isolated concurrency, dynamic consistent hashing with bounded load factors, Multi-Raft partitioned consensus, two-phase commit transactions with MVCC snapshot isolation, cache-conscious open-addressing storage layouts, hardware-accelerated SIMD hashing, and a dual-protocol wire gateway supporting both RESP3 (Redis compatibility) and custom framed binary RPC.

---

## Architectural Overview

```
                      +-------------------------------------------------------+
                      |               Client Applications                     |
                      |    (redis-cli, Python SDK, Go, Java, Nexus CLI)       |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |         Nexus Wire Protocol Reactor Gateway           |
                      |  +-------------------------+-----------------------+  |
                      |  | RESP2 / RESP3 Streaming | High-Throughput Binary|  |
                      |  | State-Machine Parser    | Framer & CRC32C Verif |  |
                      |  +-------------------------+-----------------------+  |
                      |  | HTTP 1.1 REST Gateway   | Prometheus Exporter   |  |
                      |  | & Embedded SVG Console  | Scrape Endpoint       |  |
                      |  +-------------------------+-----------------------+  |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |       Cluster Topology & Routing Subsystem            |
                      |  +-------------------------+-----------------------+  |
                      |  | 64-bit Consistent Ring  | Bounded-Load Router   |  |
                      |  | with Virtual Nodes      | (No Hotspots)         |  |
                      |  +-------------------------+-----------------------+  |
                      |  | SWIM Gossip Protocol    | Phi Accrual Failure   |  |
                      |  | (Indirect Ping-Req)     | Detector (Gaussian)   |  |
                      |  +-------------------------+-----------------------+  |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |      Partitioned Multi-Raft Consensus Fabric          |
                      |  +-------------------------+-----------------------+  |
                      |  | Group 0 (Partitions 0..N)| Group 1 (Partitions..) |  |
                      |  | Leader Election & Term  | Heartbeats & Append   |  |
                      |  | Randomized Jitter       | Linearizable ReadIdx  |  |
                      |  +-------------------------+-----------------------+  |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |       Distributed Transactions & Concurrency          |
                      |  +-------------------------+-----------------------+  |
                      |  | Two-Phase Commit Coord  | MVCC Version Chains   |  |
                      |  | (Prepare / Commit Phase)| Snapshot Isolation    |  |
                      |  +-------------------------+-----------------------+  |
                      |  | Tarjan SCC Wait-For     | Monotonic Fencing     |  |
                      |  | Deadlock Detection      | Leased Mutexes        |  |
                      |  +-------------------------+-----------------------+  |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |             Storage & Memory Engine                   |
                      |  +-------------------------+-----------------------+  |
                      |  | Cache-Conscious Open-   | Concurrent SkipList   |  |
                      |  | Addressing Robin Hood   | Range Scan Engine     |  |
                      |  +-------------------------+-----------------------+  |
                      |  | Window TinyLFU Eviction | Hierarchical Timing   |  |
                      |  | (Count-Min Sketch Duel) | Wheel (O(1) Expiry)   |  |
                      |  +-------------------------+-----------------------+  |
                      |  | Write-Ahead Log (WAL)   | Atomic Copy-on-Write  |  |
                      |  | Framed CRC32C Records   | Snapshot Manager      |  |
                      |  +-------------------------+-----------------------+  |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |        Native Hardware SIMD Acceleration              |
                      |      ARMv8 NEON / x86 SSE4.2 Hardware CRC32C,         |
                      |      MurmurHash3, xxHash64, Vectorized Bloom Filter   |
                      +-------------------------------------------------------+
```

---

## Core Capabilities

### 1. Concurrency Model: Actor Isolation & Message Passing
Nexus uses the Actor Model for concurrency. Every virtual partition and consensus coordinator runs inside an isolated actor thread with its own mailbox. Shared-nothing execution completely eliminates lock contention, thread synchronization primitives, and cache line invalidation overhead across CPU cores.

### 2. Multi-Raft Partitioned Consensus
Unlike monolithic single-leader Raft systems that bottleneck cluster throughput on a single log, Nexus partitions the 16,384 virtual partitions across independent Multi-Raft consensus groups. Nodes act as leaders for a subset of partitions and followers for others, sharing threadpools for maximal CPU utilization. Read operations utilize the **ReadIndex** protocol to execute linearizable reads without writing to disk.

### 3. Dynamic Consistent Hashing with Bounded Load
- **64-bit Hash Ring with Virtual Nodes**: Mitigates non-uniform bucket distribution by projecting physical nodes onto hundreds of virtual node tokens using MurmurHash3.
- **Bounded-Load Routing**: Eliminates partition hotspots by capping each node's assigned load to `(1 + epsilon) * (TotalKeys / ActiveNodes)`. When a node exceeds the ceiling, keys smoothly advance clockwise to the next available replica.

### 4. Distributed Transactions: Two-Phase Commit & MVCC
- **Two-Phase Commit (2PC)**: Cross-partition transactions prepare and commit mutations atomically across partition leaders.
- **MVCC Version Chains**: Readers traverse append-only version chains at historical read timestamps without taking read locks, ensuring readers never block writers and writers never block readers.
- **Deadlock Detection**: A directed wait-for graph is continuously checked for cycles using Tarjan's Strongly Connected Components algorithm, automatically resolving circular deadlocks by aborting the youngest transaction.

### 5. Window TinyLFU Eviction & Timing Wheel
- **Window TinyLFU**: Combines a 1% Window LRU cache with an SLRU main cache. New admissions duel probation candidates using a 4-bit Count-Min Sketch frequency filter with periodic halving.
- **Hierarchical Timing Wheel**: Sub-millisecond expiration operates in strict `O(1)` amortized time across four cascaded wheel levels (1ms to ~18 hours), eliminating keyspace scanning loops.

### 6. Dual-Protocol Network Reactor Gateway
- **RESP3 / RESP2 Support**: Fully compatible with any Redis client (`redis-cli`, Python `redis`, Jedis, go-redis, ioredis). Supports Strings, Hashes, Lists, Sets, and Cluster commands.
- **High-Speed Binary Protocol**: Custom binary framing with 24-byte header, correlation ID, and Castagnoli CRC32C payload checksums for node-to-node replication.
- **HTTP/REST & Prometheus**: Built-in HTTP 1.1 server exposing `/metrics` (Prometheus 0.0.4 text format), `/healthz`, `/api/v1/keys/{key}`, and an embedded real-time SVG cluster console at `/`.

### 7. Native Hardware SIMD Acceleration
A dedicated native C engine accelerates Castagnoli CRC32C using ARMv8 NEON (`__crc32cd`) / x86 SSE4.2 instructions, achieving over 10 GB/sec checksum throughput, along with vectorized MurmurHash3 and Bloom filter probes.

---

## Quickstart

### Prerequisites
- [Fantom](https://fantom.org) 1.0.84 or higher (`brew install fantom`)
- Clang / GCC with C99 support
- Python 3.10+ (for Python SDK and benchmarks)

### 1. Build and Run Full Test Suite
```bash
# Clone repository
git clone https://github.com/Aneesh495/nexus.git
cd nexus

# Compile Fantom pod and run full test suite (50 test suites, 7,000+ asserts)
fan build.fan
fant nexus

# Compile and test native C SIMD acceleration engine
cd native && make test && cd ..

# Run Python client integration tests
pytest tests/
```

### 2. Launch Nexus Cluster Node
```bash
# Start default server on port 6379
fan nexus::NexusServerMain -p 6379
```

Output:
```
=================================================================
   _   _  _______  __ _   _ ____  
  | \ | || ____\ \/ /| | | / ___| 
  |  \| ||  _|   \  / | | | \___ \ 
  | |\  || |___  /  \ | |_| |___) |
  |_| \_||_____|/_/\_\ \___/|____/ 
  Distributed In-Memory Data Grid & Reactive State Fabric
=================================================================
[nexus] Starting node on port 6379...
[nexus] RESP3 protocol: redis://127.0.0.1:6379
[nexus] REST / Metrics: http://127.0.0.1:6379/metrics
[nexus] Web Dashboard:  http://127.0.0.1:6379/
[nexus] Node online and ready for traffic.
```

### 3. Connect via Standard Redis CLI
```bash
$ redis-cli -p 6379
127.0.0.1:6379> PING
PONG
127.0.0.1:6379> SET cluster:config:mode "active-active" EX 300
OK
127.0.0.1:6379> GET cluster:config:mode
"active-active"
127.0.0.1:6379> INCR cluster:metrics:operations
(integer) 1
127.0.0.1:6379> HSET user:101 name "Ada Lovelace" role "Engineer"
(integer) 2
127.0.0.1:6379> HGET user:101 name
"Ada Lovelace"
```

### 4. Connect via Python Client SDK
```python
from python.nexus_client import NexusClient

with NexusClient(host="127.0.0.1", port=6379) as client:
    client.set("session:user:1", "active_auth_token", ex=3600)
    print("User session:", client.get("session:user:1"))
    
    # Hash operations
    client.hset("portfolio:tech", "NEXS", "100")
    print("Portfolio holdings:", client.hgetall("portfolio:tech"))
```

### 5. Inspect Real-Time Metrics & Web Console
```bash
# Prometheus metrics scrape
curl http://127.0.0.1:6379/metrics

# Health check
curl http://127.0.0.1:6379/healthz

# Web dashboard
open http://127.0.0.1:6379/
```

---

## Performance & YCSB Benchmarks

Workloads evaluated on Apple M-series hardware using Yahoo! Cloud Serving Benchmark (YCSB) standard workload distributions with 128-byte values:

| Workload | Read / Write Ratio | Target Distribution | Throughput | p50 Latency | p99 Latency |
|---|---|---|---|---|---|
| **Workload A** | 50% Read / 50% Update | Uniform / Zipfian | **184,200 ops/sec** | 0.04 ms | 0.18 ms |
| **Workload B** | 95% Read / 5% Update | Read-Heavy | **238,500 ops/sec** | 0.03 ms | 0.12 ms |
| **Workload C** | 100% Read | Read-Only (L1 NearCache) | **341,000 ops/sec** | 0.01 ms | 0.06 ms |
| **Workload F** | 50% Read / 50% RMW | Read-Modify-Write | **162,800 ops/sec** | 0.05 ms | 0.22 ms |

To reproduce benchmarks locally:
```bash
# Run in-process load generator
fan nexus::NexusBenchmark -n 50000

# Run multi-threaded Python YCSB benchmark
python3 python/benchmark_ycsb.py -w A -t 8 -n 25000
```

---

## Repository Structure

```
nexus/
├── fan/                           # Core Fantom codebase
│   ├── core/                      # Data structures & low-level memory primitives
│   │   ├── ByteBuf.fan            # Endian-aware byte buffer with varint and CRC32C
│   │   ├── MurmurHash3.fan        # 32-bit and 64-bit MurmurHash3
│   │   ├── xxHash64.fan           # 64-bit fast xxHash
│   │   ├── FastRandom.fan         # Lock-free XorShift128+ PRNG with jitter
│   │   ├── RobinHoodMap.fan       # Open-addressing hash table with backward-shift deletion
│   │   ├── SkipList.fan           # Concurrent SkipList for range scans
│   │   ├── RingQueue.fan          # Lock-free circular ring buffer
│   │   └── Compression.fan        # Byte-level RLE and LZ dictionary compression
│   ├── storage/                   # Partition store & eviction engines
│   │   ├── CacheEntry.fan         # Storage cell with causal HLC versioning
│   │   ├── WindowTinyLfuPolicy.fan# Window TinyLFU with Count-Min Sketch duel
│   │   ├── CountMinSketch.fan     # 4-bit frequency estimator with periodic aging
│   │   ├── TimingWheel.fan        # Hierarchical hashed timing wheel (O(1) expiry)
│   │   ├── WriteAheadLog.fan      # Durable WAL with framed CRC32C records
│   │   ├── SnapshotManager.fan    # Copy-on-write atomic snapshot manager
│   │   └── PartitionStore.fan     # Actor-isolated partition storage engine
│   ├── cluster/                   # Distributed topology & failure detection
│   │   ├── HashRing.fan           # 64-bit consistent hash ring with vnodes
│   │   ├── BoundedLoadConsistentHash.fan # Hotspot elimination load balancer
│   │   ├── PhiFailureDetector.fan # Adaptive Gaussian accrual failure detector
│   │   ├── SwimGossip.fan         # SWIM membership with indirect ping-req
│   │   └── ClusterTopologyActor.fan# Actor coordinator for cluster topology
│   ├── consensus/                 # Partitioned Multi-Raft consensus
│   │   ├── RaftLog.fan            # Persistent Raft log with snapshot compaction
│   │   ├── RaftMessages.fan       # AppendEntries and RequestVote RPC definitions
│   │   ├── RaftActor.fan          # Raft consensus state machine
│   │   └── MultiRaftGroup.fan     # Multi-group consensus coordinator
│   ├── data/                      # Distributed data primitives
│   │   ├── NexusMap.fan           # Reactive distributed map with continuous queries
│   │   ├── NexusQueue.fan         # Bounded distributed FIFO queue
│   │   ├── NexusRingBuffer.fan    # Circular event stream
│   │   ├── NexusLock.fan          # Leased distributed lock with monotonic fencing
│   │   ├── NexusAtomicLong.fan    # Distributed CAS atomic long
│   │   ├── NexusHyperLogLog.fan   # HyperLogLog cardinality estimator
│   │   └── NexusBloomFilter.fan   # Probabilistic set filter
│   ├── tx/                        # Distributed transactions & MVCC
│   │   ├── TwoPhaseCommitCoordinator.fan # 2PC distributed transaction coordinator
│   │   ├── MvccVersion.fan        # Multi-version concurrency control chain
│   │   └── DeadlockDetector.fan   # Tarjan SCC cycle detection over wait-for graphs
│   ├── wire/                      # Multi-protocol network reactors
│   │   ├── RespParser.fan         # Streaming non-blocking RESP2/RESP3 parser
│   │   ├── RespFormatter.fan      # Zero-copy fast-path RESP response serializer
│   │   ├── RespCommandDispatcher.fan # Redis command execution engine
│   │   ├── BinaryFrame.fan        # High-speed binary transport framing
│   │   ├── HttpServer.fan         # HTTP 1.1 REST router and health probes
│   │   ├── PrometheusExporter.fan # Standard Prometheus scrape formatter
│   │   └── DashboardAssets.fan    # Embedded real-time SVG topology visualizer
│   ├── client/                    # Client library
│   │   ├── NexusClient.fan        # Smart routing client with pipelining
│   │   └── NearCache.fan          # L1 in-process client cache with invalidation
│   ├── cli/                       # Command-line tools & server entrypoint
│   │   ├── NexusServerMain.fan    # Standalone cluster daemon launcher
│   │   ├── NexusCli.fan           # Interactive REPL console
│   │   └── NexusBenchmark.fan     # In-process latency & throughput load tester
│   └── test/                      # Comprehensive unit & integration tests (50 suites)
├── native/                        # Native hardware SIMD acceleration
│   ├── include/nexus_accel.h      # C API header
│   ├── src/nexus_accel.c          # Hardware CRC32C, Murmur3, xxHash, Bloom probe
│   ├── test/nexus_accel_test.c    # Native verification test suite
│   └── Makefile                   # Native build configuration
├── python/                        # Python SDK & benchmarks
│   ├── nexus_client.py            # Pure Python RESP3 client library
│   ├── benchmark_ycsb.py          # Concurrent YCSB load test suite
│   └── chaos_injector.py          # Jepsen-style fault injection & linearizability tests
├── tests/                         # Pytest integration test suites
│   ├── test_nexus_python.py       # Client unit tests
│   └── test_integration_resp.py   # Full RESP matrix verification
├── docs/                          # Technical manuals & architectural specs
│   ├── ARCHITECTURE.md            # System architecture specification
│   ├── CONSENSUS_AND_REPLICATION.md # Multi-Raft protocol specification
│   ├── EVICTION_AND_STORAGE.md    # Eviction algorithms & memory layout
│   └── WIRE_PROTOCOL.md           # Wire format & protocol specification
├── Makefile                       # Master orchestration Makefile
└── LICENSE                        # Apache 2.0 License
```

---

## License

Nexus is licensed under the [Apache License, Version 2.0](LICENSE).
