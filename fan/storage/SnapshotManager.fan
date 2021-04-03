**
** SnapshotManager: Point-in-time consistent partition snapshot creator and restorer.
**
** Features:
** - Atomic write using temporary file and atomic rename.
** - CRC32C checksum verification preventing corrupted snapshot restores.
** - Fast dictionary and run-length compression of partition entries.
** - Checkpoint LSN tracking to enable WAL log pruning.
**
class SnapshotManager
{
  static const Int magic := 0x534E4150 // "SNAP"

  **
  ** Create snapshot of partition store at checkpoint LSN and write to target file.
  ** Returns total bytes written.
  **
  static Int createSnapshot(PartitionStore store, Int checkpointLsn, File targetFile)
  {
    payload := ByteBuf()
    payload.writeI4(store.partitionId)
    payload.writeI8(checkpointLsn)
    payload.writeI8(DateTime.now.toJava)
    payload.writeI4(store.size)

    // Serialize each entry
    store.range("", "\uFFFF", store.size + 10).each |entry, _|
    {
      payload.writeUtf8(entry.key)
      Codec.encode(entry.val, payload)
      Codec.encode(entry.version, payload)
      payload.writeI8(entry.expireTime)
      payload.writeI8(entry.createTime)
    }

    // Compress payload using LZ dictionary compressor
    compressed := Compression.compressLz(payload)
    compLen := compressed.readableBytes
    crc := compressed.crc32c

    // Frame layout
    frame := ByteBuf(20 + compLen)
    frame.writeI4(magic)
    frame.writeI4(store.partitionId)
    frame.writeI8(checkpointLsn)
    frame.writeI4(compLen)
    frame.writeI4(crc)
    frame.writeBuf(compressed)

    // Write to temporary file, then atomic rename
    tmpFile := targetFile.parent.plus(`temp_${DateTime.nowTicks}.snap`)
    out := tmpFile.out
    buf := frame.toBuf
    out.writeBuf(buf)
    out.flush
    out.close

    tmpFile.rename(targetFile.name)
    return targetFile.size
  }

  **
  ** Restore partition store from snapshot file. Returns number of recovered entries.
  **
  static Int restoreSnapshot(PartitionStore store, File snapshotFile)
  {
    if (!snapshotFile.exists) throw IOErr("Snapshot file not found: $snapshotFile")

    in := snapshotFile.in
    rawBuf := in.readAllBuf
    in.close

    src := ByteBuf.fromBuf(rawBuf)
    if (src.readableBytes < 24) throw IOErr("Corrupted snapshot file: header underflow")

    m := src.readU4
    if (m != magic) throw IOErr("Invalid snapshot magic: 0x${m.toHex}")

    partId := src.readI4
    lsn    := src.readI8
    compLen := src.readI4
    crc    := src.readU4

    if (src.readableBytes < compLen) throw IOErr("Corrupted snapshot: unexpected EOF")

    compSlice := src.slice(compLen)
    actualCrc := compSlice.crc32c
    if (actualCrc != crc)
    {
      throw IOErr("Snapshot CRC32C mismatch: expected 0x${crc.toHex}, actual 0x${actualCrc.toHex}")
    }

    // Decompress
    payload := Compression.decompressLz(compSlice)
    pPartId := payload.readI4
    pLsn    := payload.readI8
    pTime   := payload.readI8
    pCount  := payload.readI4

    recovered := 0
    nowMillis := DateTime.now.toJava

    for (i := 0; i < pCount; ++i)
    {
      k := payload.readUtf8
      v := Codec.decode(payload)
      ver := (HybridLogicalClock)Codec.decode(payload)
      exp := payload.readI8
      created := payload.readI8

      ttl := (exp > 0) ? (exp - nowMillis).max(1) : 0
      store.put(k, v, ttl, ver, created)
      recovered++
    }

    return recovered
  }
}
