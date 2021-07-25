# Eviction Algorithms & Storage Engine Architecture
## Mathematical Formulations, Memory Layouts, and Data Structures

---

### 1. Window TinyLFU Eviction Engine

Traditional Least Recently Used (LRU) policies suffer from cache pollution during large sequential scans where infrequently accessed items evict frequently accessed items. Least Frequently Used (LFU) requires high metadata overhead and suffers from historical frequency accumulation where obsolete items linger in the cache.

Nexus resolves this with **Window TinyLFU**, combining Segmented LRU (SLRU) with an adaptive Count-Min Sketch frequency filter:

```
                           +------------------------+
                           |     Incoming Key       |
                           +-----------+------------+
                                       |
                                       v
                           +------------------------+
                           |   Window Cache (1%)    |
                           |       (LRU Queue)      |
                           +-----------+------------+
                                       |
                                (victim candidate)
                                       v
                              /------------------\
                             /   Frequency Duel   \
                            |   Window Victim vs   |
                            |  Probation Victim    |
                             \--------------------/
                                /              \
                 (higher freq) /                \ (lower freq)
                              v                  v
             +--------------------+          +--------------------+
             | Main Cache (99%)   |          |      Evicted       |
             | Protected / Probation|        +--------------------+
             +--------------------+
```

#### Count-Min Sketch Frequency Estimator
- **4-bit Counters**: Counters saturate at 15, reducing memory footprint to 4 bits per bucket (2 counters per byte).
- **Multiple Hashes**: 4 independent 64-bit hash functions derived from MurmurHash3 and xxHash64 seeds:
  ```
  index_i = (h1 + i * h2) % sketch_width
  ```
- **Conservative Update**: On read access, the sketch inspects all 4 target counters; only counters equal to the minimum value are incremented. This significantly diminishes estimation bias.
- **Periodic Aging**: A reset counter tracks total admissions. When the counter reaches sample size `W` (e.g. 10 * capacity), all 4-bit counters across the entire table are halved using bitwise shifts:
  ```
  counter = counter >> 1
  ```
  This creates an exponential recency decay, allowing stale popular keys to be replaced by newly emerging hot keys.

#### Adaptive Window Sizing via Hill Climbing
The Window cache size dynamically adjusts between 0.5% and 10% of total capacity using a hill-climbing optimization feedback loop:
- The engine monitors hit ratios across measurement epochs.
- If stepping the window size up increases hit ratio, it continues stepping in that direction; if hit ratio falls, it reverses direction.

---

### 2. Hierarchical Timing Wheel Expiration Engine

Naive timer implementations maintain priority queues with `O(log N)` insertion and cancellation overhead, or scan keys sequentially with `O(N)` cost. Nexus employs a **Hierarchical Hashed Timing Wheel** providing strict `O(1)` amortized timer scheduling:

```
+-----------------------------------------------------------------+
| Level 0: 256 slots x 1 ms     = 256 ms span (fine resolution)   |
+-----------------------------------------------------------------+
                              ^ (cascades down)
+-----------------------------------------------------------------+
| Level 1: 64 slots x 256 ms    = 16.384 seconds span             |
+-----------------------------------------------------------------+
                              ^ (cascades down)
+-----------------------------------------------------------------+
| Level 2: 64 slots x 16.384 s  = 17.47 minutes span              |
+-----------------------------------------------------------------+
                              ^ (cascades down)
+-----------------------------------------------------------------+
| Level 3: 64 slots x 17.47 min = 18.64 hours span (coarse)       |
+-----------------------------------------------------------------+
```

- When a key is stored with TTL `delta`, the expiration deadline `t_exp = t_now + delta` is computed.
- If `delta < 256ms`, the timer is placed directly in Level 0 at `slot = (t_now + delta) & 255`.
- Coarser intervals land in upper wheels. When lower wheels complete a full revolution, the upper wheel advances by one slot and cascades all residing timers down to lower levels.

---

### 3. Open-Addressing Robin Hood Hash Table

`RobinHoodMap` is a cache-conscious hash table designed for minimum CPU cache line misses and predictable search times:

- **Backing Array Layout**: Contiguous array of 64-bit bucket descriptors and object references.
- **Probe Sequence Length (PSL)**: The number of probes required to locate an element from its initial hash bucket.
- **Robin Hood Invariant**: When inserting, if the item being inserted has traveled farther from its home bucket than the current occupant (`psl_insert > psl_occupant`), the items are swapped, "taking from the rich to give to the poor".
- **Backward Shift Deletion**: When an entry is deleted, subsequent elements in the cluster are shifted back by one slot as long as their PSL is greater than zero. This avoids tombstone accumulation and maintains uniform probe distances.

---

### 4. Write-Ahead Log (WAL) Binary Framing

All persistent partition mutations append framed records to the Write-Ahead Log prior to memory modification:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Magic (0x57414C52 "WALR")                |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Record Type  |                   Reserved                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Monotonic Sequence (LSN)                   |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Payload Length                         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     CRC32C Checksum                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Payload Data ...                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Every record is framed by a 20-byte header containing record type, 64-bit log sequence number (LSN), 32-bit payload length, and Castagnoli CRC32C checksum. During recovery, the WAL reader sequentially decodes and validates every frame, immediately halting upon detecting bit rot or partial torn writes.
