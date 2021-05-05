**
** Unit tests for RaftLog replication, conflict truncation, and compaction.
**
class RaftLogTest : Test
{
  Void testAppendAndInspection()
  {
    log := RaftLog()
    verifyEq(log.lastIndex, 0)
    verifyEq(log.lastTerm, 0)
    verifyEq(log.size, 0)

    // Append 5 entries in term 1
    for (i := 1; i <= 5; ++i)
    {
      log.append(RaftLogEntry(i, 1, RaftEntryType.command, "cmd-$i"))
    }

    verifyEq(log.lastIndex, 5)
    verifyEq(log.lastTerm, 1)
    verifyEq(log.size, 5)

    verifyEq(log.termAt(3), 1)
    verifyEq(log.entryAt(3).payload, "cmd-3")
    verifyEq(log.termAt(6), -1)
    verifyNull(log.entryAt(6))

    // Range query
    range := log.entriesFrom(2, 3)
    verifyEq(range.size, 3)
    verifyEq(range[0].index, 2)
    verifyEq(range[2].index, 4)
  }

  Void testLogMatching()
  {
    log := RaftLog()
    log.append(RaftLogEntry(1, 1))
    log.append(RaftLogEntry(2, 1))
    log.append(RaftLogEntry(3, 2))

    verifyTrue(log.matchTerm(0, 0))
    verifyTrue(log.matchTerm(1, 1))
    verifyTrue(log.matchTerm(2, 1))
    verifyTrue(log.matchTerm(3, 2))

    // Term mismatch
    verifyFalse(log.matchTerm(2, 2))
    // Missing index
    verifyFalse(log.matchTerm(4, 2))
  }

  Void testTruncateAndAppendConflict()
  {
    log := RaftLog()
    // Initial entries: 1:term1, 2:term1, 3:term1, 4:term1
    for (i := 1; i <= 4; ++i)
    {
      log.append(RaftLogEntry(i, 1, RaftEntryType.command, "old-$i"))
    }

    // Leader sends conflicting entries starting at index 3 with term 2
    leaderEntries := [
      RaftLogEntry(3, 2, RaftEntryType.command, "new-3"),
      RaftLogEntry(4, 2, RaftEntryType.command, "new-4"),
      RaftLogEntry(5, 2, RaftEntryType.command, "new-5")
    ]

    log.truncateAndAppend(3, leaderEntries)

    verifyEq(log.lastIndex, 5)
    verifyEq(log.lastTerm, 2)
    verifyEq(log.termAt(2), 1)
    verifyEq(log.termAt(3), 2)
    verifyEq(log.entryAt(3).payload, "new-3")
    verifyEq(log.entryAt(5).payload, "new-5")
  }

  Void testSnapshotCompaction()
  {
    log := RaftLog()
    for (i := 1; i <= 10; ++i)
    {
      log.append(RaftLogEntry(i, i <= 5 ? 1 : 2, RaftEntryType.command, "data-$i"))
    }
    verifyEq(log.lastIndex, 10)
    verifyEq(log.size, 10)

    // Compact up to index 6 (term 2)
    log.compact(6, 2)

    verifyEq(log.compactedIndex, 6)
    verifyEq(log.compactedTerm, 2)
    verifyEq(log.size, 4) // entries 7, 8, 9, 10 remaining
    verifyEq(log.lastIndex, 10)
    verifyEq(log.lastTerm, 2)

    // Index 6 returns compacted term
    verifyEq(log.termAt(6), 2)
    // Index 5 was compacted out
    verifyEq(log.termAt(5), -1)
    verifyNull(log.entryAt(5))

    // Indices 7..10 accessible
    verifyEq(log.termAt(7), 2)
    verifyEq(log.entryAt(7).payload, "data-7")
    verifyEq(log.entryAt(10).payload, "data-10")

    // Append post-compaction
    log.append(RaftLogEntry(11, 2, RaftEntryType.command, "data-11"))
    verifyEq(log.lastIndex, 11)
    verifyEq(log.size, 5)
  }

  Void testResetToSnapshot()
  {
    log := RaftLog()
    log.append(RaftLogEntry(1, 1))
    log.append(RaftLogEntry(2, 1))

    log.resetToSnapshot(100, 5)
    verifyEq(log.compactedIndex, 100)
    verifyEq(log.compactedTerm, 5)
    verifyEq(log.lastIndex, 100)
    verifyEq(log.lastTerm, 5)
    verifyEq(log.size, 0)

    log.append(RaftLogEntry(101, 5, RaftEntryType.command, "snap-cmd"))
    verifyEq(log.lastIndex, 101)
    verifyEq(log.size, 1)
  }
}
