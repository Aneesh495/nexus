**
** RaftLog: Replicated log abstraction with offset index mapping,
** conflict reconciliation, and snapshot compaction.
**
** Reference:
** Ongaro and Ousterhout, "In Search of an Understandable Consensus Algorithm",
** USENIX Annual Technical Conference (ATC) 2014.
**
class RaftLog
{
  private Int snapshotIndex := 0
  private Int snapshotTerm := 0
  private RaftLogEntry[] entries := RaftLogEntry[,]

  new make(Int initialSnapshotIndex := 0, Int initialSnapshotTerm := 0)
  {
    this.snapshotIndex = initialSnapshotIndex
    this.snapshotTerm  = initialSnapshotTerm
  }

  **
  ** Highest log index currently stored in log (or snapshotIndex if empty).
  **
  Int lastIndex()
  {
    if (entries.isEmpty) return snapshotIndex
    return entries.last.index
  }

  **
  ** Term of the highest log entry stored (or snapshotTerm if empty).
  **
  Int lastTerm()
  {
    if (entries.isEmpty) return snapshotTerm
    return entries.last.term
  }

  **
  ** Current snapshot index boundary.
  **
  Int compactedIndex() { return snapshotIndex }

  **
  ** Current snapshot term boundary.
  **
  Int compactedTerm() { return snapshotTerm }

  **
  ** Total number of uncompacted entries held in memory.
  **
  Int size() { return entries.size }

  **
  ** Check if an entry exists at the specified index.
  **
  Bool containsIndex(Int index)
  {
    return index >= snapshotIndex && index <= lastIndex
  }

  **
  ** Lookup term of entry at specified index. Returns -1 if index is invalid or pruned.
  **
  Int termAt(Int index)
  {
    if (index == snapshotIndex) return snapshotTerm
    if (index < snapshotIndex || index > lastIndex) return -1

    offset := index - snapshotIndex - 1
    return entries[offset].term
  }

  **
  ** Lookup entry at specified index. Returns null if compacted or out of bounds.
  **
  RaftLogEntry? entryAt(Int index)
  {
    if (index <= snapshotIndex || index > lastIndex) return null
    offset := index - snapshotIndex - 1
    return entries[offset]
  }

  **
  ** Fetch a range of entries starting at fromIndex up to maxCount.
  **
  RaftLogEntry[] entriesFrom(Int fromIndex, Int maxCount := 100)
  {
    if (fromIndex > lastIndex || fromIndex <= snapshotIndex) return RaftLogEntry[,]
    startOffset := fromIndex - snapshotIndex - 1
    count := maxCount.min(entries.size - startOffset)
    return entries[startOffset..<startOffset + count]
  }

  **
  ** Append an entry to the tail of the log.
  **
  Void append(RaftLogEntry entry)
  {
    expectedIndex := lastIndex + 1
    if (entry.index != expectedIndex)
    {
      throw ArgErr("Non-contiguous append: expected $expectedIndex, got $entry.index")
    }
    entries.add(entry)
  }

  **
  ** Match and reconcile entries from leader AppendEntries RPC.
  ** Replaces any conflicting entries from matchIndex onward and appends remaining.
  **
  Void truncateAndAppend(Int fromIndex, RaftLogEntry[] newEntries)
  {
    if (newEntries.isEmpty) return

    newEntries.each |entry|
    {
      idx := entry.index
      if (idx <= snapshotIndex)
      {
        // Already compacted, skip
        return
      }

      if (idx <= lastIndex)
      {
        existingTerm := termAt(idx)
        if (existingTerm != entry.term)
        {
          // Conflict: truncate from this index onward
          offset := idx - snapshotIndex - 1
          entries.removeRange(offset..<entries.size)
          entries.add(entry)
        }
      }
      else
      {
        entries.add(entry)
      }
    }
  }

  **
  ** Check if previous log index and term match our local log (Raft log matching property).
  **
  Bool matchTerm(Int prevLogIndex, Int prevLogTerm)
  {
    if (prevLogIndex == 0) return true
    term := termAt(prevLogIndex)
    return term == prevLogTerm
  }

  **
  ** Compact and prune log entries up to and including snapshotIndex.
  **
  Void compact(Int newSnapshotIndex, Int newSnapshotTerm)
  {
    if (newSnapshotIndex <= snapshotIndex) return

    if (newSnapshotIndex >= lastIndex)
    {
      // Snapshot covers entire log
      entries.clear
    }
    else
    {
      cutOffset := newSnapshotIndex - snapshotIndex
      entries.removeRange(0..<cutOffset)
    }

    this.snapshotIndex = newSnapshotIndex
    this.snapshotTerm  = newSnapshotTerm
  }

  **
  ** Reset log after installing an external snapshot.
  **
  Void resetToSnapshot(Int newSnapshotIndex, Int newSnapshotTerm)
  {
    entries.clear
    this.snapshotIndex = newSnapshotIndex
    this.snapshotTerm  = newSnapshotTerm
  }
}
