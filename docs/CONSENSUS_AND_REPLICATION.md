# Multi-Raft Consensus & Log Replication Protocol
## Protocol Specification & State Machine Invariants

Nexus implements a distributed Multi-Raft consensus engine to provide linearizable consistency across horizontal partitions while preserving multi-core parallel throughput.

---

### 1. Multi-Raft Partitioning Model

Single-group consensus protocols bottleneck throughput because all cluster mutations must pass through a single leader log. Nexus partitions the global keyspace into independent consensus groups:

```
Keyspace [0 .. 16383 Partitions]
  |
  +---> Group 0: Partitions [0 .. 5460]     (Leader: Node-A, Followers: Node-B, Node-C)
  +---> Group 1: Partitions [5461 .. 10922] (Leader: Node-B, Followers: Node-C, Node-A)
  +---> Group 2: Partitions [10923 .. 16383](Leader: Node-C, Followers: Node-A, Node-B)
```

Each physical node acts simultaneously as leader for a subset of groups and follower for others. All consensus groups share the actor threadpool, eliminating per-partition thread allocation overhead.

---

### 2. Consensus State Machine & Election Safety

Every node in a Raft group transitions through three distinct roles: `follower`, `candidate`, and `leader`.

```
                    +--------------------------------+
                    |                                |
                    v                                |
              +------------+   Times out,            |
              |  Follower  |   starts election       |
              +-----+------+                         |
                    |                                |
                    v                                |
              +------------+   Votes from majority   |
              | Candidate  +--------------------+    |
              +-----+------+                    |    |
                    |                           v    |
                    | Discover leader     +-----+------+
                    | or higher term      |   Leader   |
                    +-------------------->+------------+
```

#### Election Invariants
1. **Election Timeout Jitter**: Randomized timeout interval `T ~ U(150ms, 300ms)` driven by `FastRandom` PRNG to avoid split votes.
2. **Term Monotonicity**: A node only grants its vote to candidate `C` in term `T` if:
   - `T > currentTerm`
   - `votedFor == null || votedFor == C.id`
   - Candidate log is at least as up to date as local log:
     ```
     C.lastLogTerm > local.lastLogTerm ||
     (C.lastLogTerm == local.lastLogTerm && C.lastLogIndex >= local.lastLogIndex)
     ```
3. **Leader Completeness**: If a log entry is committed in a given term, that entry will be present in the logs of the leaders for all higher-numbered terms.

---

### 3. Log Replication & Commit Pipeline

When a client submits a write proposal:
1. Leader appends new entry to its local `RaftLog`.
2. Leader generates `AppendEntriesRequest` containing:
   - `term`: current election term
   - `leaderId`: leader network identity
   - `prevLogIndex`: index of entry immediately preceding new entries
   - `prevLogTerm`: term of `prevLogIndex` entry
   - `entries`: batch of new log entries
   - `leaderCommit`: leader commitIndex
3. Followers verify log matching property:
   - If follower does not contain an entry at `prevLogIndex` matching `prevLogTerm`, it rejects the append request.
   - Follower returns conflict hint (`conflictIndex`, `conflictTerm`) allowing the leader to back up `nextIndex` in `O(1)` RPC roundtrips rather than decrementing by one.
4. When a quorum acknowledges append, leader advances `commitIndex` and applies entry to local `PartitionStore`.
5. Next heartbeat propagates `leaderCommit` to followers, triggering follower state machine execution.

---

### 4. Linearizable ReadIndex Protocol

To achieve linearizable reads without writing to disk or replicating read log entries:
1. **Record Commit Index**: Leader records its current `commitIndex` as `readIndex`.
2. **Quorum Heartbeat Verification**: Leader broadcasts lightweight heartbeat ping to all peers.
3. **Quorum Confirmation**: Upon receiving majority confirmation, the leader proves it was not deposed during a network partition.
4. **State Machine Sync**: Leader waits for its state machine apply index to reach at least `readIndex`.
5. **Local Execution**: Query executes against local in-memory store and returns to client.

---

### 5. Compaction & Atomic Snapshot Transfer

To prevent unbounded log growth:
- **Snapshot Trigger**: When uncompacted log entries exceed configured threshold (e.g. 50,000 entries), an atomic Copy-On-Write snapshot is created.
- **Log Compaction**: Entries prior to `snapshotIndex` are discarded; `snapshotIndex` and `snapshotTerm` are preserved as base index.
- **InstallSnapshot RPC**: If a slow or partitioned follower falls behind the leader's oldest retained log entry, the leader streams the snapshot file with framing and CRC32C validation, resetting the follower directly to the snapshot state.
