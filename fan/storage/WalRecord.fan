**
** WalRecord: Encapsulates a durable write-ahead log entry with framing and CRC32C validation.
**
** Wire Frame Layout:
** [Magic: 2B (0x574C)]
** [OpCode: 1B]
** [LSN: 8B]
** [PartitionId: 4B]
** [PayloadLen: 4B]
** [CRC32C: 4B]
** [PayloadBytes: PayloadLen]
**
class WalRecord
{
  static const Int magic := 0x574C

  static const Int opPut           := 0x01
  static const Int opDelete        := 0x02
  static const Int opClear         := 0x03
  static const Int opTxPrepare     := 0x04
  static const Int opTxCommit      := 0x05
  static const Int opTxAbort       := 0x06
  static const Int opSnapshotStart := 0x07
  static const Int opSnapshotEnd   := 0x08

  Int lsn
  Int opCode
  Int partitionId
  Str? key
  Obj? val
  HybridLogicalClock version
  Str? txId

  **
  ** Create new WAL record.
  **
  new make(
    Int lsn,
    Int opCode,
    Int partitionId,
    Str? key,
    Obj? val,
    HybridLogicalClock version,
    Str? txId := null)
  {
    this.lsn         = lsn
    this.opCode      = opCode
    this.partitionId = partitionId
    this.key         = key
    this.val         = val
    this.version     = version
    this.txId        = txId
  }

  **
  ** Serialize this record into a ByteBuf.
  **
  ByteBuf serialize()
  {
    // First, encode payload
    payloadBuf := ByteBuf()
    payloadBuf.writeUtf8(key ?: "")
    Codec.encode(val, payloadBuf)
    Codec.encode(version, payloadBuf)
    payloadBuf.writeUtf8(txId ?: "")

    payloadLen := payloadBuf.readableBytes
    crc := payloadBuf.crc32c

    // Frame header + payload
    frame := ByteBuf(23 + payloadLen)
    frame.writeI2(magic)
    frame.writeByte(opCode)
    frame.writeI8(lsn)
    frame.writeI4(partitionId)
    frame.writeI4(payloadLen)
    frame.writeI4(crc)
    frame.writeBuf(payloadBuf)

    return frame
  }

  **
  ** Deserialize next record from source ByteBuf. Returns null if incomplete.
  **
  static WalRecord? deserialize(ByteBuf src)
  {
    if (src.readableBytes < 23) return null

    src.markReaderIndex
    m := src.readU2
    if (m != magic)
    {
      src.resetReaderIndex
      throw IOErr("Corrupted WAL record: invalid magic 0x${m.toHex}")
    }

    op   := src.readByte
    lsn  := src.readI8
    part := src.readI4
    pLen := src.readI4
    crc  := src.readU4

    if (src.readableBytes < pLen)
    {
      // Incomplete frame: rewind and wait for more data
      src.resetReaderIndex
      return null
    }

    payloadSlice := src.slice(pLen)
    actualCrc := payloadSlice.crc32c
    if (actualCrc != crc)
    {
      throw IOErr("WAL record checksum mismatch at LSN $lsn: expected 0x${crc.toHex}, actual 0x${actualCrc.toHex}")
    }

    kStr := payloadSlice.readUtf8
    k := kStr.isEmpty ? null : kStr
    v := Codec.decode(payloadSlice)
    ver := (HybridLogicalClock)Codec.decode(payloadSlice)
    txStr := payloadSlice.readUtf8
    tx := txStr.isEmpty ? null : txStr

    return WalRecord(lsn, op, part, k, v, ver, tx)
  }

  override Str toStr()
  {
    return "WalRecord(lsn=$lsn, op=$opCode, part=$partitionId, k=$key, ver=$version)"
  }
}
