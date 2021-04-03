**
** Unit tests for SnapshotManager creation and restoration.
**
class SnapshotTest : Test
{
  Void testSnapshotRoundtrip()
  {
    tempDir := Env.cur.tempDir.plus(`snap_test_${DateTime.nowTicks}/`).create
    try
    {
      store1 := PartitionStore(5, 100)
      hlc := HybridLogicalClock.now

      store1.put("user:101", ["name": "Alice", "balance": 1500], 0, hlc)
      store1.put("user:102", ["name": "Bob", "balance": 2400], 0, hlc)
      store1.put("config:theme", "dark", 0, hlc)

      verifyEq(store1.size, 3)

      snapFile := tempDir.plus(`partition_005.snap`)
      bytesWritten := SnapshotManager.createSnapshot(store1, 150, snapFile)
      verify(bytesWritten > 0)
      verify(snapFile.exists)

      // Restore into a fresh partition store
      store2 := PartitionStore(5, 100)
      verifyEq(store2.size, 0)

      recovered := SnapshotManager.restoreSnapshot(store2, snapFile)
      verifyEq(recovered, 3)
      verifyEq(store2.size, 3)

      e1 := store2.get("user:101")
      verify(e1 != null)
      m1 := (Map)e1.val
      verifyEq(m1["name"], "Alice")
      verifyEq(m1["balance"], 1500)

      e2 := store2.get("config:theme")
      verifyEq(e2.val, "dark")
    }
    finally
    {
      tempDir.delete
    }
  }

  Void testSnapshotCorruptedCrc()
  {
    tempDir := Env.cur.tempDir.plus(`snap_corrupt_${DateTime.nowTicks}/`).create
    try
    {
      store := PartitionStore(0, 50)
      store.put("k", "v")
      snapFile := tempDir.plus(`part_0.snap`)
      SnapshotManager.createSnapshot(store, 10, snapFile)

      // Corrupt file
      in := snapFile.in
      bytes := in.readAllBuf
      in.close

      // Tamper byte near end
      bytes[bytes.size - 2] = bytes[bytes.size - 2].xor(0xAA)
      out := snapFile.out
      out.writeBuf(bytes)
      out.flush
      out.close

      restorerStore := PartitionStore(0, 50)
      verifyErr(IOErr#)
      {
        SnapshotManager.restoreSnapshot(restorerStore, snapFile)
      }
    }
    finally
    {
      tempDir.delete
    }
  }
}
