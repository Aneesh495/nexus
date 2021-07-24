# Nexus Distributed In-Memory Data Grid & Reactive State Fabric
## System Architecture & Engineering Specification

Nexus is an ultra-low-latency, partition-tolerant distributed in-memory data grid (IMDG) and reactive state fabric. Built from fundamental computer science primitives, Nexus combines lock-free actor concurrency, dynamic consistent hashing with bounded load factors, Multi-Raft partitioned consensus, two-phase commit transaction coordination with multi-version concurrency control (MVCC), cache-conscious storage layouts, and dual-protocol network reactors (RESP3 and high-speed binary framing).

```
                      +-------------------------------------------------------+
                      |               Client Applications                     |
                      |   (redis-cli, Jedis, go-redis, Python SDK, CLI)      |
                      +---------------------------+---------------------------+
                                                  |
                                                  v
                      +-------------------------------------------------------+
                      |         Nexus Wire Protocol Reactor Gateway           |
                      |  +-------------------------+-----------------------+  |
                      |  | RESP2 / RESP3 Streaming | High-Throughput Binary|  |
                      |  | Parser & Zero-Copy Fmt  | Framer & CRC32C Verif |  |
                      |  +-------------------------+-----------------------+  |
                      |  | HTTP 1.1 REST Gateway   | Prometheus Exporter   |  |
                      |  | & SVG Topology Console  | Scrape Endpoint       |  |
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

### 1. Concurrency Model: Actor Isolation & Message Passing

Nexus is engineered entirely upon the Actor Model to eliminate thread contention, mutual exclusion deadlocks, and cache coherence invalidation overhead.

- **Thread Isolation**: Every partition and cluster coordinator runs inside a dedicated Actor with an isolated mailbox queue.
- **Shared-Nothing State**: Mutable state (`PartitionStore`, `RaftState`, `ClusterTopologyState`) is confined strictly within an actor thread. Cross-actor interaction occurs exclusively via immutable message passing.
- **Backpressure Regulation**: Network listeners utilize bounded actor mailboxes to apply backpressure back to TCP sockets when request ingestion outpaces consensus replication.

---

### 2. Cluster Topology & Partition Routing

Nexus groups keyspace into 16,384 virtual partitions distributed deterministically across active nodes.

#### Consistent Hashing Ring with Virtual Nodes
The keyspace ring spans `[0, 2^64 - 1]`. Each physical node registers multiple virtual nodes (vnodes, default 128) across the ring hashed via MurmurHash3.
- Key lookup uses binary search over a sorted token array in `O(log V)` time.
- Replicas are chosen by walking clockwise along the ring, skipping virtual nodes belonging to already-selected physical nodes to enforce physical failure domain isolation.

#### Bounded-Load Consistent Hashing
Standard consistent hashing suffers from Poisson variance where some nodes receive up to `3x` average load. Nexus implements the bounded-load algorithm:
```
LoadCeiling = ceil( (TotalActiveKeys / ActiveNodes) * (1 + epsilon) )
```
When assigning a key, if the primary consistent hash candidate's current load exceeds `LoadCeiling`, the router continues clockwise to the next candidate whose load is below the ceiling. This strictly bounds maximum load to `1 + epsilon` (typically 1.15 to 1.25) while preserving minimal key relocation during cluster membership changes.

#### Failure Detection & SWIM Gossip
- **SWIM Protocol**: Periodic randomized probing pinging targets with `O(1)` message overhead. If direct ping fails, the node issues indirect ping requests (`ping-req`) via `k` randomly selected peers.
- **Phi Accrual Failure Detector**: Rather than binary up/down flags, Nexus computes a continuous suspicion value `phi`:
```
phi = -log10( P_later(t - t_last) )
```
where heartbeat inter-arrival times are modeled with a sliding window Gaussian distribution. When network conditions degrade, `phi` rises smoothly, allowing the cluster to adaptively adjust failover timeouts without false positives.

---

### 3. Storage Hierarchy & Eviction Architecture

Nexus employs a multi-tiered memory and storage architecture designed for sub-millisecond retrieval and durable durability:

```
+-------------------------------------------------------+
|  L1 NearCache (In-Process Client Memory)              |
|  - Zero network overhead                              |
|  - LRU eviction + invalidation listeners              |
+---------------------------+---------------------------+
                            | (cache miss)
                            v
+-------------------------------------------------------+
|  L2 PartitionStore (Actor-Isolated RAM)               |
|  - RobinHoodMap (open-addressing, linear probing)     |
|  - Concurrent SkipList (ordered ranges)               |
|  - Window TinyLFU (SLRU + 4-bit CountMinSketch)       |
|  - Hierarchical Timing Wheel (O(1) sub-ms expiry)     |
+---------------------------+---------------------------+
                            | (dirty flush / write-behind)
                            v
+-------------------------------------------------------+
|  L3 Durable Storage (Disk Persistence)                |
|  - Write-Ahead Log (WAL) with CRC32C framing          |
|  - Copy-On-Write (COW) atomic snapshot manager        |
+-------------------------------------------------------+
```

#### Cache-Conscious Robin Hood Hash Table
Internal dictionary storage uses open addressing with linear probing and Robin Hood displacement:
- On insertion, if the existing element at a bucket has a smaller probe sequence length (PSL) than the element being inserted, the elements are swapped and the displaced element continues probing.
- Backward-shift deletion shifts following entries backward until reaching an entry at its home bucket, eliminating deletion tombstones and keeping average PSL under 2.5 even at 90% load factor.

#### Window TinyLFU Eviction Policy
Combines the benefits of recency and frequency:
1. **Window Cache (LRU)**: 1% of total capacity admits all new items to capture temporary bursts.
2. **Main Cache (Segmented LRU)**: Divided into Protected (80%) and Probation (20%) segments.
3. **Count-Min Sketch Duel**: When the Window cache is full, its eviction victim duels the Probation victim. A 4-bit Count-Min Sketch with 4 independent hash functions and periodic 4-bit halving estimates access frequency. The item with higher historical frequency is retained.

#### Hierarchical Hashed Timing Wheel
Expiration timers operate in `O(1)` time using a multi-level timing wheel:
- Level 0: 256 slots at 1ms resolution (spans 0 to 255ms).
- Level 1: 64 slots at 256ms resolution (spans ~16 seconds).
- Level 2: 64 slots at ~16s resolution (spans ~17 minutes).
- Level 3: 64 slots at ~17m resolution (spans ~18 hours).
Timers cascade down to fine-grained wheels as time advances, eliminating linear scans over the keyspace.

---

### 4. Distributed Transactions & Consensus

#### Multi-Raft Architecture
Rather than bottlenecking the entire cluster on a single Raft leader, Nexus assigns partitions to independent consensus groups (`MultiRaftGroup`). Each group manages consensus log replication, leader elections with randomized jitter timeouts, and commit advancement independently across shared threadpools.

#### Linearizable ReadIndex
Read operations bypass the Raft log by executing the ReadIndex protocol:
1. Leader records its current commit index.
2. Leader exchanges a heartbeat with a quorum of followers to ensure it has not been deposed.
3. Once quorum confirms leadership, the leader awaits state machine application up to the recorded index and returns the result.

#### Two-Phase Commit with Deadlock Detection
Cross-partition transactions are coordinated via Two-Phase Commit (2PC):
- **Phase 1 (Prepare)**: Coordinator broadcasts prepare requests. Participants acquire row-level locks and validate version preconditions.
- **Phase 2 (Commit/Abort)**: If all participants vote prepared, coordinator appends commit record to WAL and broadcasts commit message.
- **Deadlock Resolution**: A wait-for graph is continuously analyzed using Tarjan's Strongly Connected Components algorithm. When a cycle is detected, the youngest transaction (or transaction with least acquired locks) is selected as victim and rolled back to maintain overall system throughput.
