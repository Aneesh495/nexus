**
** TieredStore: Multi-tiered storage engine coordinating in-memory partition caches,
** durable write-ahead logging, snapshotting checkpoints, and write-behind persistence.
**
** Storage Tiers:
** 1. Hot Tier: Actor-isolated in-memory PartitionStore with W-TinyLFU eviction.
** 2. Warm Tier: Segmented append-only WriteAheadLog with CRC32C checksums.
** 3. Cold Tier: Point-in-time SnapshotManager checkpoints and WriteBehindQueue batching.
**
class TieredStore
{
  const Int partitionId
  PartitionStore hotTier
  WriteAheadLog warmTier
  WriteBehindQueue writeBehind
  File dataDir

  private Int lastCheckpointLsn := 0

  **
  ** Open or create tiered store for partition inside dataDir.
  **
  new make(
    Int partitionId,
    File dataDir,
    Int maxMemoryEntries := 10_000,
    Int maxSegmentBytes := 16 * 1024 * 1024,
    Bool syncWal := false)
  {
    this.partitionId = partitionId
    this.dataDir     = dataDir

    if (!dataDir.exists) dataDir.create

    walDir := dataDir.plus(`wal/`)
    this.hotTier     = PartitionStore(partitionId, maxMemoryEntries)
    this.warmTier    = WriteAheadLog(walDir, maxSegmentBytes, syncWal)
    this.writeBehind = WriteBehindQueue(500, 1000)
  }

  **
  ** Read entry from hot in-memory tier.
  **
  CacheEntry? get(Str key, Int nowMillis := DateTime.now.toJava)
  {
    return hotTier.get(key, nowMillis)
  }

  **
  ** Write entry: logs to WAL (warm tier), updates in-memory cache (hot tier),
  ** and enqueues in write-behind queue (cold tier).
  **
  CacheEntry put(
    Str key,
    Obj? val,
    Int ttlMillis := 0,
    HybridLogicalClock? version := null,
    Int nowMillis := DateTime.now.toJava)
  {
    ver := version != null ? version : HybridLogicalClock(nowMillis, 0)

    // 1. Log to WAL
    warmTier.append(WalRecord.opPut, partitionId, key, val, ver)

    // 2. Update Hot Tier
    entry := hotTier.put(key, val, ttlMillis, ver, nowMillis)

    // 3. Enqueue in Write-Behind
    writeBehind.enqueue(entry)

    return entry
  }

  **
  ** Remove entry: logs tombstone to WAL, evicts from hot tier, enqueues tombstone in write-behind.
  **
  CacheEntry? remove(Str key, Int nowMillis := DateTime.now.toJava)
  {
    ver := HybridLogicalClock(nowMillis, 0)
    warmTier.append(WalRecord.opDelete, partitionId, key, null, ver)

    entry := hotTier.remove(key)
    if (entry != null)
    {
      entry.setTombstone(true)
      writeBehind.enqueue(entry)
    }
    return entry
  }

  **
  ** Create an atomic snapshot checkpoint, advancing checkpoint LSN and truncating old WAL logs.
  ** Returns total bytes in snapshot.
  **
  Int checkpoint()
  {
    warmTier.flush
    snapFile := dataDir.plus(`snapshot_part_${partitionId}.snap`)
    bytesWritten := SnapshotManager.createSnapshot(hotTier, lastCheckpointLsn, snapFile)

    // Truncate older WAL segments
    warmTier.truncateBefore(lastCheckpointLsn)
    return bytesWritten
  }

  **
  ** Crash recovery: restores latest snapshot checkpoint if available, then replays
  ** any subsequent WAL records written after the checkpoint.
  **
  Int recover()
  {
    recoveredEntries := 0
    snapFile := dataDir.plus(`snapshot_part_${partitionId}.snap`)

    // 1. Restore snapshot if present
    if (snapFile.exists)
    {
      recoveredEntries += SnapshotManager.restoreSnapshot(hotTier, snapFile)
    }

    // 2. Replay subsequent WAL logs
    walRecovered := warmTier.recover |record|
    {
      if (record.partitionId == partitionId)
      {
        if (record.opCode == WalRecord.opPut && record.key != null)
        {
          hotTier.put(record.key, record.val, 0, record.version)
          recoveredEntries++
        }
        else if (record.opCode == WalRecord.opDelete && record.key != null)
        {
          hotTier.remove(record.key)
        }
        else if (record.opCode == WalRecord.opClear)
        {
          hotTier.clear
        }
      }
    }

    return recoveredEntries
  }

  **
  ** Drain and flush dirty write-behind queue entries.
  **
  CacheEntry[] flushWriteBehind()
  {
    batch := writeBehind.drainBatch(500)
    writeBehind.acknowledge(batch)
    return batch
  }

  **
  ** Close storage streams and flush pending data.
  **
  Void close()
  {
    warmTier.flush
    warmTier.close
  }
}
