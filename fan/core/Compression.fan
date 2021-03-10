**
** Compression: High-speed byte-level run-length and dictionary compression routines.
**
** Tailored for:
** - In-memory partition snapshot serialization
** - Write-Ahead Log record compression
** - Cluster replication chunk compaction
**
class Compression
{
  **
  ** Compress data using fast Run-Length Encoding (RLE).
  ** Format: [control_byte] [data...]
  ** Control byte: high bit 1 = run of identical bytes (len = (ctrl & 0x7F) + 3, followed by 1 byte)
  **               high bit 0 = literal bytes (len = (ctrl & 0x7F) + 1, followed by len bytes)
  **
  static ByteBuf compressRle(ByteBuf src)
  {
    dst := ByteBuf(src.readableBytes)
    raw := src.readBytes(src.readableBytes)
    len := raw.size
    i := 0

    while (i < len)
    {
      // Check for run
      runLen := 1
      while (i + runLen < len && raw[i + runLen] == raw[i] && runLen < 130)
      {
        runLen++
      }

      if (runLen >= 3)
      {
        // Emit run
        dst.writeByte(0x80.or(runLen - 3))
        dst.writeByte(raw[i])
        i += runLen
      }
      else
      {
        // Emit literals
        litStart := i
        litLen := 0
        while (i < len && litLen < 128)
        {
          // Stop if a run of >= 3 begins
          if (i + 2 < len && raw[i] == raw[i + 1] && raw[i] == raw[i + 2]) break
          litLen++
          i++
        }
        dst.writeByte(litLen - 1)
        for (k := 0; k < litLen; ++k)
        {
          dst.writeByte(raw[litStart + k])
        }
      }
    }
    return dst
  }

  **
  ** Decompress RLE-encoded byte buffer.
  **
  static ByteBuf decompressRle(ByteBuf src)
  {
    dst := ByteBuf(src.readableBytes * 2)
    while (src.readableBytes > 0)
    {
      ctrl := src.readByte
      if (ctrl.and(0x80) != 0)
      {
        // Run
        count := ctrl.and(0x7F) + 3
        b := src.readByte
        for (k := 0; k < count; ++k)
        {
          dst.writeByte(b)
        }
      }
      else
      {
        // Literals
        count := ctrl.and(0x7F) + 1
        for (k := 0; k < count; ++k)
        {
          dst.writeByte(src.readByte)
        }
      }
    }
    return dst
  }

  **
  ** Fast byte-level LZ dictionary compressor.
  ** Scans for 4-byte matches using a 4096-entry hash table.
  **
  static ByteBuf compressLz(ByteBuf src)
  {
    dst := ByteBuf(src.readableBytes)
    raw := src.readBytes(src.readableBytes)
    len := raw.size

    // Write original uncompressed length as varint header
    dst.writeVarInt(len)
    if (len == 0) return dst

    hashTable := Int[,].fill(-1, 4096)
    litStart := 0
    i := 0

    while (i + 4 <= len)
    {
      h := (raw[i].shiftl(8).or(raw[i + 1]).xor(raw[i + 2].shiftl(4)).xor(raw[i + 3])).and(4095)
      matchPos := hashTable[h]
      hashTable[h] = i

      if (matchPos != -1 && (i - matchPos) < 65535 && (i - matchPos) > 0
          && raw[matchPos] == raw[i]
          && raw[matchPos + 1] == raw[i + 1]
          && raw[matchPos + 2] == raw[i + 2]
          && raw[matchPos + 3] == raw[i + 3])
      {
        // Match found: flush preceding literals
        litLen := i - litStart
        if (litLen > 0)
        {
          dst.writeByte(0) // Token 0: literals follow
          dst.writeVarInt(litLen)
          for (k := 0; k < litLen; ++k)
          {
            dst.writeByte(raw[litStart + k])
          }
        }

        // Extend match length
        matchLen := 4
        while (i + matchLen < len && raw[matchPos + matchLen] == raw[i + matchLen] && matchLen < 255)
        {
          matchLen++
        }

        // Token 1: match (offset: 2 bytes, length: 1 byte)
        offset := i - matchPos
        dst.writeByte(1)
        dst.writeI2(offset)
        dst.writeByte(matchLen)

        i += matchLen
        litStart = i
      }
      else
      {
        i++
      }
    }

    // Flush any remaining trailing literals
    if (litStart < len)
    {
      litLen := len - litStart
      dst.writeByte(0)
      dst.writeVarInt(litLen)
      for (k := 0; k < litLen; ++k)
      {
        dst.writeByte(raw[litStart + k])
      }
    }

    return dst
  }

  **
  ** Decompress LZ dictionary-compressed stream.
  **
  static ByteBuf decompressLz(ByteBuf src)
  {
    origLen := src.readVarInt
    dst := ByteBuf(origLen)
    if (origLen == 0) return dst

    while (src.readableBytes > 0)
    {
      token := src.readByte
      if (token == 0)
      {
        // Literals
        litLen := src.readVarInt
        for (k := 0; k < litLen; ++k)
        {
          dst.writeByte(src.readByte)
        }
      }
      else if (token == 1)
      {
        // Match
        offset := src.readU2
        matchLen := src.readByte
        // Copy matchLen bytes from (current_pos - offset)
        currPos := dst.writerIndex
        startPos := currPos - offset
        if (startPos < 0) throw IOErr("Corrupted LZ stream: invalid negative match offset")

        // Read directly from destination buffer
        for (k := 0; k < matchLen; ++k)
        {
          b := dst.peekByte(startPos + k - dst.readerIndex)
          dst.writeByte(b)
        }
      }
      else
      {
        throw IOErr("Corrupted LZ stream: unknown token $token")
      }
    }

    return dst
  }
}
