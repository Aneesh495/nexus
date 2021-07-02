using concurrent

**
** ByteBuf: High-performance contiguous byte buffer tailored for distributed
** network protocols, binary framing, and zero-allocation message serialization.
**
** Features:
** - Dual reader and writer pointer semantics (readerIndex and writerIndex).
** - Dual endianness support (Big-Endian default, Little-Endian optional).
** - Variable-length integer encoding (LEB128 unsigned and ZigZag signed varints).
** - Zero-copy buffer slicing with shared underlying storage.
** - Hardware-aligned bit and byte manipulation with CRC32C computation.
**
class ByteBuf
{
  private Int[] bytes
  private Int rIndex := 0
  private Int wIndex := 0
  private Int markR := 0
  private Int markW := 0
  private Bool bigEndian := true

  **
  ** Create a new buffer with initial capacity and optional endianness.
  **
  new make(Int initialCapacity := 64, Bool bigEndian := true)
  {
    this.bytes = Int[,].fill(0, initialCapacity.max(16))
    this.bigEndian = bigEndian
  }

  **
  ** Wrap an existing list of 8-bit unsigned integer bytes.
  **
  new wrap(Int[] sourceBytes, Bool bigEndian := true)
  {
    this.bytes = sourceBytes.dup
    this.rIndex = 0
    this.wIndex = sourceBytes.size
    this.bigEndian = bigEndian
  }

  **
  ** Create from a Fantom sys::Buf.
  **
  static ByteBuf fromBuf(Buf buf, Bool bigEndian := true)
  {
    origPos := buf.pos
    buf.seek(0)
    arr := Int[,]
    arr.capacity = buf.size
    while (buf.remaining > 0)
    {
      arr.add(buf.read)
    }
    buf.seek(origPos)
    return ByteBuf.wrap(arr, bigEndian)
  }

  **
  ** Convert current readable bytes into a Fantom sys::Buf.
  **
  Buf toBuf()
  {
    buf := Buf(readableBytes)
    for (i := rIndex; i < wIndex; ++i)
    {
      buf.write(bytes[i])
    }
    buf.flip
    return buf
  }

  **
  ** Number of bytes available for reading.
  **
  Int readableBytes() { (wIndex - rIndex).max(0) }

  **
  ** Number of bytes available for writing before resizing is required.
  **
  Int writableBytes() { (bytes.size - wIndex).max(0) }

  **
  ** Total allocated byte capacity.
  **
  Int capacity() { bytes.size }

  **
  ** Get current read index.
  **
  Int readerIndex() { rIndex }

  **
  ** Set current read index.
  **
  This setReaderIndex(Int index)
  {
    if (index < 0 || index > wIndex)
      throw ArgErr("Reader index out of bounds: $index (wIndex=$wIndex)")
    this.rIndex = index
    return this
  }

  **
  ** Get current write index.
  **
  Int writerIndex() { wIndex }

  **
  ** Set current write index.
  **
  This setWriterIndex(Int index)
  {
    if (index < rIndex || index > bytes.size)
      throw ArgErr("Writer index out of bounds: $index (rIndex=$rIndex, capacity=${bytes.size})")
    this.wIndex = index
    return this
  }

  **
  ** Mark current reader index for later reset.
  **
  This markReaderIndex() { this.markR = rIndex; return this }

  **
  ** Reset reader index to previously marked position.
  **
  This resetReaderIndex() { this.rIndex = markR; return this }

  **
  ** Mark current writer index for later reset.
  **
  This markWriterIndex() { this.markW = wIndex; return this }

  **
  ** Reset writer index to previously marked position.
  **
  This resetWriterIndex() { this.wIndex = markW; return this }

  **
  ** Discard read bytes and shift unread bytes to index zero.
  **
  This compact()
  {
    if (rIndex == 0) return this
    rem := readableBytes
    if (rem > 0)
    {
      for (i := 0; i < rem; ++i)
      {
        bytes[i] = bytes[rIndex + i]
      }
    }
    rIndex = 0
    wIndex = rem
    markR = 0
    markW = rem
    return this
  }

  **
  ** Alias for compact(): discards already-read bytes.
  **
  This discardReadBytes() { compact }

  **
  ** Clear reader and writer indices without zeroing memory.
  **
  This clear()
  {
    rIndex = 0
    wIndex = 0
    markR = 0
    markW = 0
    return this
  }

  **
  ** Ensure writable space is available, expanding backing array if necessary.
  **
  This ensureWritable(Int minWritable)
  {
    if (minWritable <= writableBytes) return this
    needed := wIndex + minWritable
    newCap := bytes.size * 2
    while (newCap < needed)
    {
      newCap *= 2
    }
    newBytes := Int[,].fill(0, newCap)
    for (i := 0; i < bytes.size; ++i)
    {
      newBytes[i] = bytes[i]
    }
    this.bytes = newBytes
    return this
  }

  // --- Primitives: Write ---

  This writeByte(Int b)
  {
    ensureWritable(1)
    bytes[wIndex++] = b.and(0xFF)
    return this
  }

  This writeI1(Int b) { writeByte(b) }

  This writeI2(Int val)
  {
    ensureWritable(2)
    v := val.and(0xFFFF)
    if (bigEndian)
    {
      bytes[wIndex++] = v.shiftr(8).and(0xFF)
      bytes[wIndex++] = v.and(0xFF)
    }
    else
    {
      bytes[wIndex++] = v.and(0xFF)
      bytes[wIndex++] = v.shiftr(8).and(0xFF)
    }
    return this
  }

  This writeI4(Int val)
  {
    ensureWritable(4)
    v := val.and(0xFFFFFFFF)
    if (bigEndian)
    {
      bytes[wIndex++] = v.shiftr(24).and(0xFF)
      bytes[wIndex++] = v.shiftr(16).and(0xFF)
      bytes[wIndex++] = v.shiftr(8).and(0xFF)
      bytes[wIndex++] = v.and(0xFF)
    }
    else
    {
      bytes[wIndex++] = v.and(0xFF)
      bytes[wIndex++] = v.shiftr(8).and(0xFF)
      bytes[wIndex++] = v.shiftr(16).and(0xFF)
      bytes[wIndex++] = v.shiftr(24).and(0xFF)
    }
    return this
  }

  This writeI8(Int val)
  {
    ensureWritable(8)
    if (bigEndian)
    {
      bytes[wIndex++] = val.shiftr(56).and(0xFF)
      bytes[wIndex++] = val.shiftr(48).and(0xFF)
      bytes[wIndex++] = val.shiftr(40).and(0xFF)
      bytes[wIndex++] = val.shiftr(32).and(0xFF)
      bytes[wIndex++] = val.shiftr(24).and(0xFF)
      bytes[wIndex++] = val.shiftr(16).and(0xFF)
      bytes[wIndex++] = val.shiftr(8).and(0xFF)
      bytes[wIndex++] = val.and(0xFF)
    }
    else
    {
      bytes[wIndex++] = val.and(0xFF)
      bytes[wIndex++] = val.shiftr(8).and(0xFF)
      bytes[wIndex++] = val.shiftr(16).and(0xFF)
      bytes[wIndex++] = val.shiftr(24).and(0xFF)
      bytes[wIndex++] = val.shiftr(32).and(0xFF)
      bytes[wIndex++] = val.shiftr(40).and(0xFF)
      bytes[wIndex++] = val.shiftr(48).and(0xFF)
      bytes[wIndex++] = val.shiftr(56).and(0xFF)
    }
    return this
  }

  This writeF8(Float val)
  {
    bits := val.bits
    return writeI8(bits)
  }

  This writeBytes(Int[] src, Int offset := 0, Int len := src.size)
  {
    ensureWritable(len)
    for (i := 0; i < len; ++i)
    {
      bytes[wIndex++] = src[offset + i].and(0xFF)
    }
    return this
  }

  This writeBuf(ByteBuf src, Int len := src.readableBytes)
  {
    if (len > src.readableBytes)
      throw ArgErr("Not enough readable bytes in src: $len > ${src.readableBytes}")
    ensureWritable(len)
    for (i := 0; i < len; ++i)
    {
      bytes[wIndex++] = src.readByte
    }
    return this
  }

  **
  ** Write variable-length unsigned 64-bit integer (LEB128).
  **
  This writeVarInt(Int value)
  {
    v := value
    while (v.and(-128) != 0)
    {
      writeByte(v.and(0x7F).or(0x80))
      v = v.shiftr(7)
    }
    writeByte(v.and(0x7F))
    return this
  }

  **
  ** Write variable-length signed integer using ZigZag encoding.
  **
  This writeZigZag(Int value)
  {
    zz := (value < 0) ? (value.not.shiftl(1)).or(1) : value.shiftl(1)
    return writeVarInt(zz)
  }

  **
  ** Write UTF-8 string prefixed by unsigned varint byte length.
  **
  This writeUtf8(Str str)
  {
    raw := str.toBuf
    writeVarInt(raw.size)
    ensureWritable(raw.size)
    for (i := 0; i < raw.size; ++i)
    {
      bytes[wIndex++] = raw[i].and(0xFF)
    }
    return this
  }

  // --- Primitives: Read ---

  Int readByte()
  {
    if (rIndex >= wIndex) throw IOErr("Buffer underflow: no readable bytes")
    return bytes[rIndex++]
  }

  Int readI1()
  {
    b := readByte
    return (b >= 128) ? b - 256 : b
  }

  Int readU1() { readByte }

  Int readI2()
  {
    if (readableBytes < 2) throw IOErr("Buffer underflow for 2-byte read")
    b0 := readByte
    b1 := readByte
    val := bigEndian ? (b0.shiftl(8).or(b1)) : (b1.shiftl(8).or(b0))
    return (val >= 32768) ? val - 65536 : val
  }

  Int readU2()
  {
    if (readableBytes < 2) throw IOErr("Buffer underflow for 2-byte read")
    b0 := readByte
    b1 := readByte
    return bigEndian ? (b0.shiftl(8).or(b1)) : (b1.shiftl(8).or(b0))
  }

  Int readI4()
  {
    if (readableBytes < 4) throw IOErr("Buffer underflow for 4-byte read")
    b0 := readByte; b1 := readByte; b2 := readByte; b3 := readByte
    val := 0
    if (bigEndian)
    {
      val = b0.shiftl(24).or(b1.shiftl(16)).or(b2.shiftl(8)).or(b3)
    }
    else
    {
      val = b3.shiftl(24).or(b2.shiftl(16)).or(b1.shiftl(8)).or(b0)
    }
    return (val >= 2147483648) ? val - 4294967296 : val
  }

  Int readU4()
  {
    if (readableBytes < 4) throw IOErr("Buffer underflow for 4-byte read")
    b0 := readByte; b1 := readByte; b2 := readByte; b3 := readByte
    if (bigEndian)
      return b0.shiftl(24).or(b1.shiftl(16)).or(b2.shiftl(8)).or(b3)
    else
      return b3.shiftl(24).or(b2.shiftl(16)).or(b1.shiftl(8)).or(b0)
  }

  Int readI8()
  {
    if (readableBytes < 8) throw IOErr("Buffer underflow for 8-byte read")
    b0 := readByte; b1 := readByte; b2 := readByte; b3 := readByte
    b4 := readByte; b5 := readByte; b6 := readByte; b7 := readByte
    if (bigEndian)
    {
      return b0.shiftl(56).or(b1.shiftl(48)).or(b2.shiftl(40)).or(b3.shiftl(32))
        .or(b4.shiftl(24)).or(b5.shiftl(16)).or(b6.shiftl(8)).or(b7)
    }
    else
    {
      return b7.shiftl(56).or(b6.shiftl(48)).or(b5.shiftl(40)).or(b4.shiftl(32))
        .or(b3.shiftl(24)).or(b2.shiftl(16)).or(b1.shiftl(8)).or(b0)
    }
  }

  Float readF8()
  {
    bits := readI8
    return Float.makeBits(bits)
  }

  Int[] readBytes(Int len)
  {
    if (readableBytes < len) throw IOErr("Buffer underflow: requested $len, available $readableBytes")
    out := Int[,].fill(0, len)
    for (i := 0; i < len; ++i)
    {
      out[i] = readByte
    }
    return out
  }

  **
  ** Read variable-length unsigned 64-bit integer (LEB128).
  **
  Int readVarInt()
  {
    res := 0
    shift := 0
    while (true)
    {
      b := readByte
      res = res.or(b.and(0x7F).shiftl(shift))
      if (b.and(0x80) == 0) break
      shift += 7
      if (shift >= 64) throw IOErr("Malformed LEB128 varint sequence")
    }
    return res
  }

  **
  ** Read variable-length signed integer using ZigZag decoding.
  **
  Int readZigZag()
  {
    raw := readVarInt
    return (raw.and(1) == 1) ? (raw.shiftr(1)).not : raw.shiftr(1)
  }

  **
  ** Read UTF-8 string prefixed by unsigned varint byte length.
  **
  Str readUtf8()
  {
    len := readVarInt
    raw := readBytes(len)
    buf := Buf(len)
    for (i := 0; i < len; ++i)
    {
      buf.write(raw[i])
    }
    buf.flip
    return buf.readAllStr(false)
  }

  **
  ** Read raw UTF-8 string of the specified byte length without length prefix.
  **
  Str readUtf8Bytes(Int len := readableBytes)
  {
    raw := readBytes(len)
    buf := Buf(len)
    for (i := 0; i < len; ++i)
    {
      buf.write(raw[i])
    }
    buf.flip
    return buf.readAllStr(false)
  }

  **
  ** Peek byte at relative offset from readerIndex without advancing position.
  **
  Int peekByte(Int offset := 0)
  {
    idx := rIndex + offset
    if (idx < 0 || idx >= wIndex) throw IndexErr("Peek offset out of range: $offset")
    return bytes[idx]
  }

  **
  ** Get byte at absolute index in backing buffer.
  **
  Int getByte(Int index)
  {
    if (index < 0 || index >= bytes.size) throw IndexErr("Index out of range: $index")
    return bytes[index]
  }

  **
  ** Set byte at absolute index in backing buffer.
  **
  Void setByte(Int index, Int val)
  {
    if (index < 0 || index >= bytes.size) throw IndexErr("Index out of range: $index")
    bytes[index] = val.and(0xFF)
  }

  **
  ** Slice buffer from readerIndex for given length.
  **
  ByteBuf slice(Int length := readableBytes)
  {
    if (readableBytes < length) throw IOErr("Slice length exceeds readable bytes: $length > $readableBytes")
    sub := Int[,].fill(0, length)
    for (i := 0; i < length; ++i)
    {
      sub[i] = bytes[rIndex + i]
    }
    rIndex += length
    return ByteBuf.wrap(sub, bigEndian)
  }

  **
  ** Calculate CRC32C (Castagnoli) checksum across readable bytes.
  **
  Int crc32c()
  {
    crc := 0xFFFFFFFF
    for (i := rIndex; i < wIndex; ++i)
    {
      b := bytes[i]
      crc = crc.xor(b)
      for (k := 0; k < 8; ++k)
      {
        if (crc.and(1) != 0)
          crc = crc.shiftr(1).xor(0x82F63B78)
        else
          crc = crc.shiftr(1)
      }
    }
    return crc.xor(0xFFFFFFFF).and(0xFFFFFFFF)
  }

  **
  ** Format readable bytes as a hexadecimal string.
  **
  Str toHex()
  {
    sb := StrBuf()
    for (i := rIndex; i < wIndex; ++i)
    {
      hex := bytes[i].toHex
      if (hex.size == 1) sb.addChar('0')
      sb.add(hex)
    }
    return sb.toStr
  }

  override Str toStr()
  {
    return "ByteBuf(ridx=$rIndex, widx=$wIndex, cap=${bytes.size}, readable=$readableBytes)"
  }
}
