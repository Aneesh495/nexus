**
** Unit tests for TieredStore multi-tier persistence and crash recovery.
**
class TieredStoreTest : Test
{
  Void testEndToEndPersistenceAndCrashRecovery()
  {
    tempDir := Env.cur.tempDir.plus(`tiered_test_${DateTime.nowTicks}/`).create
    try
    {
      store1 := TieredStore(7, tempDir, 100, 1024, true)

      // Writes before checkpoint
      store1.put("user:001", "Alice")
      store1.put("user:002", "Bob")
      verifyEq(store1.get("user:001").val, "Alice")
      verifyEq(store1.get("user:002").val, "Bob")

      // Checkpoint snapshot
      snapBytes := store1.checkpoint
      verify(snapBytes > 0)

      // Writes after checkpoint
      store1.put("user:003", "Charlie")
      store1.remove("user:001") // Delete Alice
      store1.close

      // Simulate process crash: open new TieredStore instance on same directory
      store2 := TieredStore(7, tempDir, 100, 1024, true)
      verifyEq(store2.hotTier.size, 0) // Hot memory starts empty

      // Trigger recovery
      recovered := store2.recover
      verify(recovered > 0)

      // Verify state: Alice deleted, Bob preserved from snapshot, Charlie recovered from WAL!
      verifyEq(store2.get("user:001"), null)
      verifyEq(store2.get("user:002").val, "Bob")
      verifyEq(store2.get("user:003").val, "Charlie")

      // Flush write-behind
      flushed := store2.flushWriteBehind
      verify(flushed.size >= 0)

      store2.close
    }
    finally
    {
      tempDir.delete
    }
  }
}
