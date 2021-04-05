**
** WriteBehindQueue: Asynchronous write-coalescing buffer for persistent storage tiers.
**
** Properties:
** - Write Coalescing: Multiple rapid updates to the same key are collapsed into
**   a single write operation representing the latest state.
** - Dual Flush Triggers: Batch size threshold or maximum delay interval.
** - Failure Isolation: Unflushed or errored items remain protected in retry buffers.
**
class WriteBehindQueue
{
  private Str:CacheEntry dirtyMap := Str:CacheEntry[:]
  private Str[] dirtyOrder := Str[,]
  private Int maxBatchSize
  private Int maxDelayMillis
  private Int lastFlushTime := DateTime.now.toJava

  **
  ** Create write-behind queue with batch size and delay window thresholds.
  **
  new make(Int maxBatchSize := 500, Int maxDelayMillis := 1000)
  {
    this.maxBatchSize   = maxBatchSize.max(1)
    this.maxDelayMillis = maxDelayMillis.max(10)
  }

  **
  ** Enqueue a mutated cache entry. Coalesces if key is already pending in the queue.
  **
  Void enqueue(CacheEntry entry)
  {
    entry.setDirty(true)
    if (!dirtyMap.containsKey(entry.key))
    {
      dirtyOrder.add(entry.key)
    }
    // Overwrite with latest entry state (coalesce)
    dirtyMap[entry.key] = entry
  }

  **
  ** Check if flush threshold has been reached (by batch size or time elapsed).
  **
  Bool shouldFlush(Int nowMillis := DateTime.now.toJava)
  {
    if (dirtyMap.size >= maxBatchSize) return true
    if (!dirtyMap.isEmpty && (nowMillis - lastFlushTime >= maxDelayMillis)) return true
    return false
  }

  **
  ** Drain a batch of coalesced entries for writing to persistent storage.
  **
  CacheEntry[] drainBatch(Int limit := maxBatchSize, Int nowMillis := DateTime.now.toJava)
  {
    batch := CacheEntry[,]
    batch.capacity = limit.min(dirtyMap.size)

    drainedKeys := Str[,]

    for (i := 0; i < dirtyOrder.size && batch.size < limit; ++i)
    {
      k := dirtyOrder[i]
      entry := dirtyMap.remove(k)
      if (entry != null)
      {
        batch.add(entry)
        drainedKeys.add(k)
      }
    }

    // Clean up dirtyOrder list
    dirtyOrder.removeAll(drainedKeys)
    lastFlushTime = nowMillis
    return batch
  }

  **
  ** Acknowledge successful flush, clearing dirty flags on flushed entries.
  **
  Void acknowledge(CacheEntry[] flushedEntries)
  {
    for (i := 0; i < flushedEntries.size; ++i)
    {
      flushedEntries[i].setDirty(false)
    }
  }

  **
  ** Re-enqueue failed entries back into the dirty buffer.
  **
  Void retry(CacheEntry[] failedEntries)
  {
    for (i := 0; i < failedEntries.size; ++i)
    {
      enqueue(failedEntries[i])
    }
  }

  **
  ** Number of dirty keys pending write-back.
  **
  Int size() { dirtyMap.size }

  **
  ** Check if no dirty keys are pending.
  **
  Bool isEmpty() { dirtyMap.isEmpty }

  **
  ** Clear all pending dirty state.
  **
  Void clear()
  {
    dirtyMap.clear
    dirtyOrder.clear
    lastFlushTime = DateTime.now.toJava
  }
}
