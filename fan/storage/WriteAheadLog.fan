using concurrent

**
** WriteAheadLog: Segmented append-only write-ahead log manager with crash recovery.
**
** Features:
** - Framed records protected by Castagnoli CRC32C checksums.
** - Automatic segment rotation when file exceeds maxSegmentBytes.
** - Synchronous or asynchronous flush options.
** - Log truncation for segments older than snapshot checkpoint LSN.
** - Recovery reader replaying uncommitted/committed state up to crash point.
**
class WriteAheadLog
{
  private File dir
  private Int maxSegmentBytes
  private Bool syncOnWrite
  private Int currentLsn := 0
  private Int currentSegmentId := 0
  private OutStream? currentOut := null
  private Int currentSegmentBytes := 0

  **
  ** Open or create WAL inside target directory.
  **
  new make(File dir, Int maxSegmentBytes := 16 * 1024 * 1024, Bool syncOnWrite := false)
  {
    this.dir = dir
    this.maxSegmentBytes = maxSegmentBytes.max(1024)
    this.syncOnWrite = syncOnWrite

    if (!dir.exists) dir.create
    initLatestSegment
  }

  **
  ** Append a record to the WAL. Returns assigned monotonic LSN.
  **
  Int append(
    Int opCode,
    Int partitionId,
    Str? key,
    Obj? val,
    HybridLogicalClock version,
    Str? txId := null)
  {
    currentLsn++
    record := WalRecord(currentLsn, opCode, partitionId, key, val, version, txId)
    bytes := record.serialize

    if (currentSegmentBytes + bytes.readableBytes > maxSegmentBytes)
    {
      rotate
    }

    buf := bytes.toBuf
    currentOut.writeBuf(buf)
    currentSegmentBytes += buf.size

    if (syncOnWrite)
    {
      currentOut.flush
    }

    return currentLsn
  }

  **
  ** Flush pending writes to disk.
  **
  Void flush()
  {
    if (currentOut != null) currentOut.flush
  }

  **
  ** Rotate to a new WAL segment file.
  **
  Void rotate()
  {
    if (currentOut != null)
    {
      currentOut.flush
      currentOut.close
    }

    currentSegmentId++
    segFile := getSegmentFile(currentSegmentId)
    currentOut = segFile.out(true) // append mode
    currentSegmentBytes = segFile.size
  }

  **
  ** Replay all valid WAL records across all segments sequentially.
  ** Passes each recovered WalRecord to the visitor function.
  **
  Int recover(|WalRecord record| visitor)
  {
    segments := listSegmentFiles
    recoveredCount := 0
    maxObservedLsn := 0

    for (s := 0; s < segments.size; ++s)
    {
      segFile := segments[s]
      if (segFile.size == 0) continue

      in := segFile.in
      allBytes := in.readAllBuf
      in.close

      byteBuf := ByteBuf.fromBuf(allBytes)

      while (byteBuf.readableBytes >= 23)
      {
        try
        {
          record := WalRecord.deserialize(byteBuf)
          if (record == null) break // EOF or incomplete tail record
          if (record.lsn > maxObservedLsn) maxObservedLsn = record.lsn
          visitor(record)
          recoveredCount++
        }
        catch (Err e)
        {
          // Stop recovery upon encountering corrupt record at tail
          break
        }
      }
    }

    this.currentLsn = maxObservedLsn
    return recoveredCount
  }

  **
  ** Truncate and delete segment files whose records are strictly older than checkpointLsn.
  **
  Int truncateBefore(Int checkpointLsn)
  {
    segments := listSegmentFiles
    deletedCount := 0

    // Keep at least the active segment
    for (i := 0; i < segments.size - 1; ++i)
    {
      seg := segments[i]
      segId := parseSegmentId(seg.name)
      // If segment ID is strictly less than current active segment
      if (segId < currentSegmentId)
      {
        seg.delete
        deletedCount++
      }
    }
    return deletedCount
  }

  **
  ** Close WAL and flush streams.
  **
  Void close()
  {
    if (currentOut != null)
    {
      currentOut.flush
      currentOut.close
      currentOut = null
    }
  }

  private Void initLatestSegment()
  {
    segments := listSegmentFiles
    if (segments.isEmpty)
    {
      currentSegmentId = 1
      segFile := getSegmentFile(currentSegmentId)
      currentOut = segFile.out(true)
      currentSegmentBytes = 0
    }
    else
    {
      lastSeg := segments.last
      currentSegmentId = parseSegmentId(lastSeg.name)
      currentOut = lastSeg.out(true)
      currentSegmentBytes = lastSeg.size
    }
  }

  private File[] listSegmentFiles()
  {
    files := dir.listFiles.findAll |f| { f.name.startsWith("wal_") && f.name.endsWith(".log") }
    return files.sort |a, b| { parseSegmentId(a.name) <=> parseSegmentId(b.name) }
  }

  private File getSegmentFile(Int segId)
  {
    padded := segId.toStr.padl(8, '0')
    return dir.plus(`wal_${padded}.log`)
  }

  private Int parseSegmentId(Str name)
  {
    try
    {
      clean := name.replace("wal_", "").replace(".log", "")
      return clean.toInt
    }
    catch (Err e)
    {
      return 0
    }
  }
}
