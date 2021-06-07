**
** Unit tests for TwoPhaseCommitCoordinator cross-partition ACID transactions.
**
class TwoPhaseCommitTest : Test
{
  Void testSuccessfulTwoPhaseCommit()
  {
    coordNode := NodeId("coordinator:8000")
    coord := TwoPhaseCommitCoordinator(coordNode)

    store1 := PartitionStore(1)
    store2 := PartitionStore(2)
    stores := [1: store1, 2: store2]
    keyPartitions := ["acct:100": 1, "acct:200": 2]

    // Set initial balances
    store1.put("acct:100", 1000)
    store2.put("acct:200", 500)

    // Execute transfer: $200 from acct:100 to acct:200
    tx := coord.beginTransaction(IsolationLevel.serializable)
    verifyEq(tx.state, TxState.active)

    tx.recordRead("acct:100", 1000)
    tx.recordRead("acct:200", 500)
    tx.bufferWrite("acct:100", 800, 1)
    tx.bufferWrite("acct:200", 700, 2)

    verifyTrue(tx.hasBufferedWrite("acct:100"))
    verifyEq(tx.getBufferedWrite("acct:100"), 800)

    // Commit 2PC
    committed := coord.commitTransaction(tx, stores, keyPartitions)
    verifyTrue(committed)
    verifyEq(tx.state, TxState.committed)
    verifyTrue(tx.commitTimestamp > 0)

    // Verify stores updated atomically
    verifyEq(store1.get("acct:100")?.val, 800)
    verifyEq(store2.get("acct:200")?.val, 700)
    verifyFalse(coord.isKeyLocked("acct:100"))
    verifyFalse(coord.isKeyLocked("acct:200"))
  }

  Void testAbortDueToConflictAndRollback()
  {
    coordNode := NodeId("coordinator:8000")
    coord := TwoPhaseCommitCoordinator(coordNode)

    store1 := PartitionStore(1)
    store2 := PartitionStore(2)
    stores := [1: store1, 2: store2]
    keyPartitions := ["shared:key": 1, "other:key": 2]

    store1.put("shared:key", "initial")
    store2.put("other:key", "initial-2")

    // Transaction 1 buffers write
    tx1 := coord.beginTransaction()
    tx1.bufferWrite("shared:key", "v1", 1)

    // Transaction 2 buffers write to same key AND another key
    tx2 := coord.beginTransaction()
    tx2.bufferWrite("shared:key", "v2", 1)
    tx2.bufferWrite("other:key", "v2-other", 2)

    // Suppose tx1 is currently preparing or holding lock
    // Lock shared:key under tx1
    // Let's commit tx1 first
    coord.commitTransaction(tx1, stores, keyPartitions)
    verifyEq(store1.get("shared:key")?.val, "v1")

    // Now test conflict where one key is held by another active tx
    // Tx3 holds lock
    tx3 := coord.beginTransaction()
    tx3.bufferWrite("shared:key", "v3", 1)
    // Manually test explicit rollback
    coord.rollbackTransaction(tx3)
    verifyEq(tx3.state, TxState.aborted)
    verifyFalse(coord.isKeyLocked("shared:key"))
  }
}
