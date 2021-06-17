**
** Binary transport frame for node-to-node RPC and high-speed binary protocol.
**
** Wire format layout:
**   [0..3]   Magic constant: 0x4E455853 ("NEXS")
**   [4]      Protocol version (1 byte, currently 1)
**   [5]      Flags (1 byte: response, compressed, heartbeat, oneway)
**   [6..7]   Message type (2 bytes, big-endian)
**   [8..15]  Correlation ID (8 bytes, big-endian)
**   [16..19] Payload length (4 bytes, big-endian)
**   [20..23] CRC32C of payload (4 bytes, big-endian)
**   [24..N]  Payload body (length bytes)
**
const class BinaryFrame
{
  static const Int magicNumber := 0x4E455853 // "NEXS"
  static const Int currentVersion := 1
  static const Int headerSize := 24

  static const Int flagResponse   := 0x01
  static const Int flagCompressed := 0x02
  static const Int flagHeartbeat  := 0x04
  static const Int flagOneway     := 0x08

  const Int version
  const Int flags
  const Int msgType
  const Int correlationId
  const Int[] payload
  const Int checksum

  new make(Int msgType, Int correlationId, Int[] payload, Int flags := 0, Int version := currentVersion)
  {
    this.version = version
    this.flags = flags
    this.msgType = msgType
    this.correlationId = correlationId
    this.payload = payload

    // Compute Castagnoli CRC32C over payload bytes
    tempBuf := ByteBuf(payload.size)
    tempBuf.writeBytes(payload)
    this.checksum = tempBuf.crc32c.and(0xFFFFFFFF)
  }

  Bool isResponse()   { flags.and(flagResponse) != 0 }
  Bool isCompressed() { flags.and(flagCompressed) != 0 }
  Bool isHeartbeat()  { flags.and(flagHeartbeat) != 0 }
  Bool isOneway()     { flags.and(flagOneway) != 0 }

  ** Serialize this frame to a ByteBuf ready for network transmission **
  ByteBuf encode()
  {
    buf := ByteBuf(headerSize + payload.size)
    buf.writeI4(magicNumber)
    buf.writeByte(version)
    buf.writeByte(flags)
    buf.writeI2(msgType)
    buf.writeI8(correlationId)
    buf.writeI4(payload.size)
    buf.writeI4(checksum)
    buf.writeBytes(payload)
    return buf
  }

  **
  ** Decode a BinaryFrame from a ByteBuf. Returns null if the buffer
  ** does not yet contain a complete frame (partial read).
  ** Throws IOErr if the magic header or checksum verification fails.
  **
  static BinaryFrame? decode(ByteBuf buf)
  {
    if (buf.readableBytes < headerSize)
      return null

    buf.markReaderIndex

    magic := buf.readI4
    if (magic != magicNumber)
    {
      buf.resetReaderIndex
      throw IOErr("Invalid frame magic: 0x${magic.toHex}, expected 0x${magicNumber.toHex}")
    }

    ver := buf.readByte
    flg := buf.readByte
    mType := buf.readI2
    corrId := buf.readI8
    payloadLen := buf.readU4
    expectedCrc := buf.readU4

    if (payloadLen < 0 || payloadLen > 64 * 1024 * 1024)
    {
      buf.resetReaderIndex
      throw IOErr("Frame payload length out of bounds: $payloadLen")
    }

    if (buf.readableBytes < payloadLen)
    {
      // Partial frame: rewind reader index and await more network data
      buf.resetReaderIndex
      return null
    }

    payloadBytes := buf.readBytes(payloadLen)

    // Verify CRC32C integrity
    checkBuf := ByteBuf(payloadLen)
    checkBuf.writeBytes(payloadBytes)
    actualCrc := checkBuf.crc32c.and(0xFFFFFFFF)

    if (actualCrc != expectedCrc)
    {
      throw IOErr("Corrupted payload CRC32C: expected 0x${expectedCrc.toHex}, got 0x${actualCrc.toHex}")
    }

    return BinaryFrame(mType, corrId, payloadBytes, flg, ver)
  }
}
