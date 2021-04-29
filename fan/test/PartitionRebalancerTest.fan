**
** Unit tests for PartitionRebalancer online state migration and catch-up replay.
**
class PartitionRebalancerTest : Test
{
  Void testEndToEndMigrationLifecycle()
  {
    srcNode := NodeId("source-node:8001")
    tgtNode := NodeId("target-node:8002")
    rebalancer := PartitionRebalancer(srcNode, 5) // chunk size = 5

    // Set up source store with 12 entries
    srcStore := PartitionStore(42)
    12.times |i|
    {
      srcStore.put("key-${i}", "val-${i}")
    }

    // Schedule migration task
    rebalancer.scheduleMigration(42, srcNode, tgtNode, 1, 12)

    task := rebalancer.getTask(42)
    verifyNotNull(task)
    verifyEq(task.state, MigrationState.pending)
    verifyEq(task.partitionId, 42)

    // Generate chunks from source store entries
    entries := srcStore.prefixScan("", 100).vals
    chunks := rebalancer.generateChunks(42, entries)
    // 12 entries with chunk size 5 => 3 chunks: [5, 5, 2]
    verifyEq(chunks.size, 3)
    verifyEq(chunks[0].entries.size, 5)
    verifyFalse(chunks[0].isFinalChunk)
    verifyEq(chunks[1].entries.size, 5)
    verifyFalse(chunks[1].isFinalChunk)
    verifyEq(chunks[2].entries.size, 2)
    verifyTrue(chunks[2].isFinalChunk)

    // Apply chunks to target store
    tgtStore := PartitionStore(42)
    rebalancer.applyChunk(chunks[0], tgtStore)
    verifyEq(task.transferredKeys, 5)
    verifyEq(task.state, MigrationState.transferring)

    rebalancer.applyChunk(chunks[1], tgtStore)
    verifyEq(task.transferredKeys, 10)

    // Simulate concurrent delta write on source during transfer
    deltaEntry := CacheEntry("key-delta", "val-delta", HybridLogicalClock(DateTime.now.toJava, 0), 0)
    rebalancer.recordDeltaWrite(42, deltaEntry)

    // Apply final chunk
    rebalancer.applyChunk(chunks[2], tgtStore)
    verifyEq(task.transferredKeys, 12)
    verifyEq(task.state, MigrationState.catch_up)

    // Replay delta writes
    replayed := rebalancer.replayDeltas(42, tgtStore)
    verifyEq(replayed, 1)
    verifyEq(task.transferredKeys, 13)
    verifyEq(tgtStore.get("key-delta")?.val, "val-delta")

    // Commit migration
    committed := rebalancer.commitMigration(42)
    verifyTrue(committed)
    verifyEq(task.state, MigrationState.committed)

    // Target store should now have all 13 entries
    verifyEq(tgtStore.size, 13)
    verifyEq(tgtStore.get("key-0")?.val, "val-0")
    verifyEq(tgtStore.get("key-11")?.val, "val-11")

    // Purge completed tasks
    rebalancer.purgeCompleted
    verifyNull(rebalancer.getTask(42))
  }

  Void testAbortMigration()
  {
    srcNode := NodeId("source-node:8001")
    tgtNode := NodeId("target-node:8002")
    rebalancer := PartitionRebalancer(srcNode, 10)

    rebalancer.scheduleMigration(99, srcNode, tgtNode, 2)

    task := rebalancer.getTask(99)
    verifyNotNull(task)

    rebalancer.abortMigration(99, "Target node connection dropped")
    verifyEq(task.state, MigrationState.aborted)
    verifyEq(task.failureReason, "Target node connection dropped")

    rebalancer.purgeCompleted
    verifyNull(rebalancer.getTask(99))
  }
}
