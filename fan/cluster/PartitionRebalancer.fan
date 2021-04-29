**
** MigrationState: Lifecycle stages of an online partition transfer.
**
enum class MigrationState
{
  pending,
  transferring,
  catch_up,
  committed,
  aborted
}

**
** MigrationChunk: Batch of key-value cache entries streamed over the wire.
**
class MigrationChunk
{
  Int partitionId
  Int chunkIndex
  Bool isFinalChunk
  CacheEntry[] entries

  new make(Int partitionId, Int chunkIndex, Bool isFinalChunk, CacheEntry[] entries)
  {
    this.partitionId  = partitionId
    this.chunkIndex   = chunkIndex
    this.isFinalChunk = isFinalChunk
    this.entries      = entries
  }
}

**
** MigrationTask: State tracking for a single partition undergoing rebalancing.
**
class MigrationTask
{
  Int partitionId
  NodeId sourceNode
  NodeId targetNode
  Int epoch
  MigrationState state := MigrationState.pending
  Int transferredKeys := 0
  Int totalKeys := 0
  Int startedMillis := 0
  Int completedMillis := 0
  Str? failureReason := null

  new make(Int partitionId, NodeId sourceNode, NodeId targetNode, Int epoch, Int totalKeys := 0)
  {
    this.partitionId = partitionId
    this.sourceNode  = sourceNode
    this.targetNode  = targetNode
    this.epoch       = epoch
    this.totalKeys   = totalKeys
  }
}

**
** PartitionRebalancer: Coordinates live partition migration between cluster nodes
** with phased chunk transfers, delta catch-up, and zero-downtime cutover.
**
class PartitionRebalancer
{
  private NodeId localNode
  private Int chunkSize
  private Int:MigrationTask activeTasks := Int:MigrationTask[:]
  private Int:CacheEntry[] deltaBuffers := Int:CacheEntry[][:]

  new make(NodeId localNode, Int chunkSize := 100)
  {
    this.localNode = localNode
    this.chunkSize = chunkSize
  }

  **
  ** Create migration tasks from a PartitionDiff and previous PartitionTable.
  **
  MigrationTask[] planMigrations(PartitionDiff diff, PartitionTable prevTable, Int:Int partitionKeyCounts := Int:Int[:])
  {
    planned := MigrationTask[,]
    diff.movedPartitions.each |partId|
    {
      newOwner := diff.newOwners[partId]
      assign   := prevTable.getAssignment(partId)
      oldOwner := assign != null ? assign.primary : null
      if (newOwner != null && oldOwner != null && newOwner != oldOwner)
      {
        total := partitionKeyCounts.get(partId, 0)
        task := MigrationTask(partId, oldOwner, newOwner, diff.newEpoch, total)
        activeTasks[partId] = task
        planned.add(task)
      }
    }
    return planned
  }

  **
  ** Manually schedule a migration task.
  **
  MigrationTask scheduleMigration(Int partitionId, NodeId sourceNode, NodeId targetNode, Int epoch, Int totalKeys := 0)
  {
    task := MigrationTask(partitionId, sourceNode, targetNode, epoch, totalKeys)
    activeTasks[partitionId] = task
    return task
  }

  **
  ** Active migration task for partition.
  **
  MigrationTask? getTask(Int partitionId)
  {
    return activeTasks[partitionId]
  }

  **
  ** All currently active tasks.
  **
  MigrationTask[] allTasks()
  {
    return activeTasks.vals
  }

  **
  ** Start streaming chunks from source store to target node.
  **
  MigrationChunk[] generateChunks(Int partitionId, CacheEntry[] partitionEntries)
  {
    task := activeTasks[partitionId]
    if (task == null) throw Err("No active migration task for partition $partitionId")

    task.state = MigrationState.transferring
    task.startedMillis = DateTime.now.toJava
    task.totalKeys = partitionEntries.size

    chunks := MigrationChunk[,]
    if (partitionEntries.isEmpty)
    {
      chunks.add(MigrationChunk(partitionId, 0, true, CacheEntry[,]))
      return chunks
    }

    numChunks := (partitionEntries.size + chunkSize - 1) / chunkSize
    numChunks.times |idx|
    {
      startIdx := idx * chunkSize
      endIdx := (startIdx + chunkSize).min(partitionEntries.size)
      isLast := (idx == numChunks - 1)
      batch := partitionEntries[startIdx..<endIdx]
      chunks.add(MigrationChunk(partitionId, idx, isLast, batch))
    }
    return chunks
  }

  **
  ** Ingest incoming chunk on target node into target store.
  **
  Int applyChunk(MigrationChunk chunk, PartitionStore targetStore)
  {
    applied := 0
    now := DateTime.now.toJava
    chunk.entries.each |entry|
    {
      ttl := (entry.expireTime > 0) ? (entry.expireTime - now).max(1) : 0
      targetStore.put(entry.key, entry.val, ttl)
      applied++
    }

    task := activeTasks[chunk.partitionId]
    if (task != null)
    {
      task.transferredKeys += applied
      if (chunk.isFinalChunk)
      {
        task.state = MigrationState.catch_up
      }
    }
    return applied
  }

  **
  ** Buffer concurrent writes occurring during migration for subsequent catch-up replay.
  **
  Void recordDeltaWrite(Int partitionId, CacheEntry writeDelta)
  {
    task := activeTasks[partitionId]
    if (task == null || task.state == MigrationState.committed || task.state == MigrationState.aborted)
    {
      return
    }

    buf := deltaBuffers[partitionId]
    if (buf == null)
    {
      buf = CacheEntry[,]
      deltaBuffers[partitionId] = buf
    }
    buf.add(writeDelta)
  }

  **
  ** Replay accumulated delta buffer to target store during catch-up phase.
  **
  Int replayDeltas(Int partitionId, PartitionStore targetStore)
  {
    task := activeTasks[partitionId]
    if (task == null) return 0

    buf := deltaBuffers[partitionId]
    if (buf == null || buf.isEmpty) return 0

    applied := 0
    now := DateTime.now.toJava
    buf.each |entry|
    {
      ttl := (entry.expireTime > 0) ? (entry.expireTime - now).max(1) : 0
      targetStore.put(entry.key, entry.val, ttl)
      applied++
    }
    deltaBuffers.remove(partitionId)
    task.transferredKeys += applied
    return applied
  }

  **
  ** Complete and commit migration task atomically.
  **
  Bool commitMigration(Int partitionId)
  {
    task := activeTasks[partitionId]
    if (task == null) return false

    task.state = MigrationState.committed
    task.completedMillis = DateTime.now.toJava
    deltaBuffers.remove(partitionId)
    return true
  }

  **
  ** Abort and rollback migration task upon failure.
  **
  Void abortMigration(Int partitionId, Str reason)
  {
    task := activeTasks[partitionId]
    if (task == null) return

    task.state = MigrationState.aborted
    task.failureReason = reason
    deltaBuffers.remove(partitionId)
  }

  **
  ** Clear finished (committed or aborted) tasks.
  **
  Void purgeCompleted()
  {
    keysToPurge := Int[,]
    activeTasks.each |task, partId|
    {
      if (task.state == MigrationState.committed || task.state == MigrationState.aborted)
      {
        keysToPurge.add(partId)
      }
    }
    keysToPurge.each |partId| { activeTasks.remove(partId) }
  }
}
