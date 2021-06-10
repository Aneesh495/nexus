**
** MvccRecord: Immutable revision in a key version chain holding timestamps,
** payload, and predecessor link.
**
** Reference:
** Bernstein and Goodman, "Concurrency Control in Distributed Database Systems", ACM Computing Surveys 1981.
**
class MvccRecord
{
  Str key
  Obj? val
  Int commitTimestamp
  Int expireTimestamp := 0 // 0 means currently active / unexpired
  Bool isTombstone
  MvccRecord? prev

  new make(
    Str key,
    Obj? val,
    Int commitTimestamp,
    Bool isTombstone := false,
    MvccRecord? prev := null)
  {
    this.key             = key
    this.val             = val
    this.commitTimestamp = commitTimestamp
    this.isTombstone     = isTombstone
    this.prev            = prev
  }

  **
  ** Check if this version was visible to a transaction reading at snapshotTimestamp.
  **
  Bool isVisibleTo(Int snapshotTimestamp)
  {
    if (commitTimestamp > snapshotTimestamp) return false
    if (expireTimestamp != 0 && expireTimestamp <= snapshotTimestamp) return false
    return true
  }
}

**
** MvccStore: Manages multi-version concurrency control chains, snapshot reads,
** and background vacuum garbage collection.
**
class MvccStore
{
  private Str:MvccRecord chains := Str:MvccRecord[:]

  **
  ** Insert or update a key at commitTimestamp.
  **
  Void put(Str key, Obj? val, Int commitTimestamp)
  {
    currLatest := chains[key]
    newRecord := MvccRecord(key, val, commitTimestamp, false, currLatest)

    if (currLatest != null)
    {
      currLatest.expireTimestamp = commitTimestamp
    }
    chains[key] = newRecord
  }

  **
  ** Delete a key by recording a tombstone version at commitTimestamp.
  **
  Void delete(Str key, Int commitTimestamp)
  {
    currLatest := chains[key]
    if (currLatest == null || currLatest.isTombstone) return

    tombstone := MvccRecord(key, null, commitTimestamp, true, currLatest)
    currLatest.expireTimestamp = commitTimestamp
    chains[key] = tombstone
  }

  **
  ** Read point-in-time value visible at readSnapshotTimestamp without acquiring locks.
  **
  Obj? get(Str key, Int readSnapshotTimestamp)
  {
    MvccRecord? curr := chains[key]
    while (curr != null)
    {
      if (curr.isVisibleTo(readSnapshotTimestamp))
      {
        return curr.isTombstone ? null : curr.val
      }
      curr = curr.prev
    }
    return null
  }

  **
  ** Get the latest committed value.
  **
  Obj? getLatest(Str key)
  {
    record := chains[key]
    if (record == null || record.isTombstone) return null
    return record.val
  }

  **
  ** Number of distinct revisions retained in version chain for key.
  **
  Int chainDepth(Str key)
  {
    depth := 0
    MvccRecord? curr := chains[key]
    while (curr != null)
    {
      depth++
      curr = curr.prev
    }
    return depth
  }

  **
  ** Vacuum and prune obsolete version revisions older than minActiveSnapshot.
  ** Returns total number of pruned dead records.
  **
  Int garbageCollect(Int minActiveSnapshot)
  {
    prunedTotal := 0
    chains.each |head, key|
    {
      MvccRecord? curr := head
      while (curr != null && curr.prev != null)
      {
        pred := curr.prev
        // If predecessor expired before oldest active snapshot, it is never visible again
        if (pred.expireTimestamp != 0 && pred.expireTimestamp <= minActiveSnapshot)
        {
          curr.prev = null // truncate tail of chain
          prunedTotal++
          break
        }
        curr = pred
      }
    }
    return prunedTotal
  }

  **
  ** Total number of managed keys.
  **
  Int keyCount() { return chains.size }

  **
  ** Clear all version chains.
  **
  Void clear()
  {
    chains.clear
  }
}
