**
** Unit tests for MvccStore version chains, snapshot isolation, and vacuum garbage collection.
**
class MvccTest : Test
{
  Void testSnapshotIsolationReads()
  {
    mvcc := MvccStore()
    verifyEq(mvcc.keyCount, 0)

    // Version 1 committed at t = 10
    mvcc.put("stock:AAPL", 150, 10)
    // Version 2 committed at t = 20
    mvcc.put("stock:AAPL", 160, 20)
    // Version 3 committed at t = 30
    mvcc.put("stock:AAPL", 175, 30)

    verifyEq(mvcc.chainDepth("stock:AAPL"), 3)
    verifyEq(mvcc.getLatest("stock:AAPL"), 175)

    // Historical snapshot reads
    verifyNull(mvcc.get("stock:AAPL", 5))        // Before version 1
    verifyEq(mvcc.get("stock:AAPL", 10), 150)    // Exact at version 1
    verifyEq(mvcc.get("stock:AAPL", 15), 150)    // Between version 1 and 2
    verifyEq(mvcc.get("stock:AAPL", 20), 160)    // Exact at version 2
    verifyEq(mvcc.get("stock:AAPL", 25), 160)    // Between version 2 and 3
    verifyEq(mvcc.get("stock:AAPL", 30), 175)    // Version 3
    verifyEq(mvcc.get("stock:AAPL", 100), 175)   // High future timestamp
  }

  Void testTombstoneDeletionHistoricalReads()
  {
    mvcc := MvccStore()
    mvcc.put("session:xyz", "active-token", 100)
    mvcc.put("session:xyz", "refreshed-token", 200)

    // Delete at t = 300
    mvcc.delete("session:xyz", 300)
    verifyEq(mvcc.chainDepth("session:xyz"), 3)
    verifyNull(mvcc.getLatest("session:xyz"))

    // Historical reads before deletion still find valid data
    verifyEq(mvcc.get("session:xyz", 150), "active-token")
    verifyEq(mvcc.get("session:xyz", 250), "refreshed-token")

    // Reads at or after t = 300 see tombstone -> return null
    verifyNull(mvcc.get("session:xyz", 300))
    verifyNull(mvcc.get("session:xyz", 400))
  }

  Void testVacuumGarbageCollection()
  {
    mvcc := MvccStore()
    // Create 5 versions: t = 10, 20, 30, 40, 50
    for (t := 1; t <= 5; ++t)
    {
      mvcc.put("counter", t * 10, t * 10)
    }
    verifyEq(mvcc.chainDepth("counter"), 5)

    // Prune versions older than minActiveSnapshot = 35
    // Versions at t = 10 and 20 expired at t = 20 and 30 <= 35, so they can be trimmed
    pruned := mvcc.garbageCollect(35)
    verifyTrue(pruned > 0)
    verifyTrue(mvcc.chainDepth("counter") < 5)

    // Latest versions (t = 40, 50) and current visible version (t = 30) remain intact
    verifyEq(mvcc.get("counter", 30), 30)
    verifyEq(mvcc.get("counter", 40), 40)
    verifyEq(mvcc.get("counter", 50), 50)
    verifyEq(mvcc.getLatest("counter"), 50)
  }
}
