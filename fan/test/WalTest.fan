**
** Unit tests for WriteAheadLog and WalRecord framing.
**
class WalTest : Test
{
  Void testRecordFramingRoundtrip()
  {
    hlc := HybridLogicalClock(1730553600000, 42)
    record := WalRecord(1, WalRecord.opPut, 7, "account:101", 5000, hlc, "tx-99")

    buf := record.serialize
    verify(buf.readableBytes >= 23)

    decoded := WalRecord.deserialize(buf)
    verify(decoded != null)
    verifyEq(decoded.lsn, 1)
    verifyEq(decoded.opCode, WalRecord.opPut)
    verifyEq(decoded.partitionId, 7)
    verifyEq(decoded.key, "account:101")
    verifyEq(decoded.val, 5000)
    verifyEq(decoded.version.physical, hlc.physical)
    verifyEq(decoded.txId, "tx-99")
  }

  Void testCorruptedRecordDetection()
  {
    hlc := HybridLogicalClock.now
    record := WalRecord(2, WalRecord.opPut, 0, "k", "v", hlc)
    buf := record.serialize

    // Tamper with a payload byte at the end of the buffer
    raw := buf.readBytes(buf.readableBytes)
    raw[raw.size - 1] = raw[raw.size - 1].xor(0xFF)
    tampered := ByteBuf.wrap(raw)

    verifyErr(IOErr#)
    {
      WalRecord.deserialize(tampered)
    }
  }

  Void testWalAppendAndRecovery()
  {
    tempDir := Env.cur.tempDir.plus(`wal_test_${DateTime.nowTicks}/`).create
    try
    {
      wal := WriteAheadLog(tempDir, 1024, true)
      hlc := HybridLogicalClock.now

      wal.append(WalRecord.opPut, 0, "k1", "v1", hlc)
      wal.append(WalRecord.opPut, 0, "k2", "v2", hlc)
      wal.append(WalRecord.opDelete, 0, "k1", null, hlc)
      wal.close

      // Recover into a partition store
      recoveredRecords := WalRecord[,]
      recoveryWal := WriteAheadLog(tempDir, 1024, false)
      count := recoveryWal.recover |record|
      {
        recoveredRecords.add(record)
      }
      recoveryWal.close

      verifyEq(count, 3)
      verifyEq(recoveredRecords.size, 3)
      verifyEq(recoveredRecords[0].key, "k1")
      verifyEq(recoveredRecords[0].opCode, WalRecord.opPut)
      verifyEq(recoveredRecords[1].key, "k2")
      verifyEq(recoveredRecords[2].key, "k1")
      verifyEq(recoveredRecords[2].opCode, WalRecord.opDelete)
    }
    finally
    {
      tempDir.delete
    }
  }

  Void testSegmentRotation()
  {
    tempDir := Env.cur.tempDir.plus(`wal_rotate_${DateTime.nowTicks}/`).create
    try
    {
      // Tiny segment size (200 bytes) to force rapid rotations
      wal := WriteAheadLog(tempDir, 200, true)
      hlc := HybridLogicalClock.now

      for (i := 0; i < 20; ++i)
      {
        wal.append(WalRecord.opPut, 0, "key-$i", "payload-data-for-rotation-testing-$i", hlc)
      }
      wal.close

      // Should have generated multiple segment files
      files := tempDir.listFiles.findAll |File f->Bool| { f.name.endsWith(".log") }
      verify(files.size >= 2)
    }
    finally
    {
      tempDir.delete
    }
  }
}
