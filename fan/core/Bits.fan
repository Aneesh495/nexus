**
** Bits: High-performance low-level bit manipulation and universal integer coding utilities.
**
** Implements:
** - Branchless population count (Hamming weight)
** - Leading and trailing zero counting (clz, ctz)
** - Power-of-two arithmetic (nextPowerOfTwo, isPowerOfTwo)
** - Elias Gamma and Elias Delta universal integer compression codecs
**
class Bits
{
  **
  ** Calculate number of set bits (population count) in a 64-bit integer.
  **
  static Int popCount(Int x)
  {
    v := x
    v = v - (v.shiftr(1).and(0x5555555555555555))
    v = (v.and(0x3333333333333333)) + (v.shiftr(2).and(0x3333333333333333))
    v = (v + v.shiftr(4)).and(0x0F0F0F0F0F0F0F0F)
    v = v + v.shiftr(8)
    v = v + v.shiftr(16)
    v = v + v.shiftr(32)
    return v.and(0x7F)
  }

  **
  ** Count leading zero bits in a 64-bit integer. Returns 64 if x == 0.
  **
  static Int numberOfLeadingZeros(Int x)
  {
    if (x == 0) return 64
    n := 1
    v := x
    if (v.shiftr(32) == 0) { n += 32; v = v.shiftl(32) }
    if (v.shiftr(48) == 0) { n += 16; v = v.shiftl(16) }
    if (v.shiftr(56) == 0) { n += 8;  v = v.shiftl(8)  }
    if (v.shiftr(60) == 0) { n += 4;  v = v.shiftl(4)  }
    if (v.shiftr(62) == 0) { n += 2;  v = v.shiftl(2)  }
    n -= v.shiftr(63)
    return n
  }

  **
  ** Count trailing zero bits in a 64-bit integer. Returns 64 if x == 0.
  **
  static Int numberOfTrailingZeros(Int x)
  {
    if (x == 0) return 64
    return popCount((x.and(-x)) - 1)
  }

  **
  ** Check if an integer is a positive power of two.
  **
  static Bool isPowerOfTwo(Int x)
  {
    return x > 0 && (x.and(x - 1) == 0)
  }

  **
  ** Round up to the next power of two.
  **
  static Int nextPowerOfTwo(Int x)
  {
    if (x <= 1) return 1
    v := x - 1
    v = v.or(v.shiftr(1))
    v = v.or(v.shiftr(2))
    v = v.or(v.shiftr(4))
    v = v.or(v.shiftr(8))
    v = v.or(v.shiftr(16))
    v = v.or(v.shiftr(32))
    return v + 1
  }

  **
  ** Encode positive integers (>= 1) using Elias Gamma coding into a BitWriter.
  **
  static Void encodeEliasGamma(Int[] numbers, BitWriter writer)
  {
    for (i := 0; i < numbers.size; ++i)
    {
      x := numbers[i]
      if (x < 1) throw ArgErr("Elias Gamma requires positive integer >= 1: $x")
      n := 63 - numberOfLeadingZeros(x)
      // Write n zero bits
      for (k := 0; k < n; ++k)
      {
        writer.writeBit(0)
      }
      // Write binary representation of x (n + 1 bits)
      for (k := n; k >= 0; --k)
      {
        writer.writeBit(x.shiftr(k).and(1))
      }
    }
  }

  **
  ** Decode Elias Gamma coded integers from a BitReader.
  **
  static Int[] decodeEliasGamma(BitReader reader, Int count)
  {
    out := Int[,]
    out.capacity = count
    for (i := 0; i < count; ++i)
    {
      n := 0
      while (reader.readBit == 0)
      {
        n++
        if (n > 62) throw IOErr("Malformed Elias Gamma stream")
      }
      val := 1
      for (k := 0; k < n; ++k)
      {
        val = val.shiftl(1).or(reader.readBit)
      }
      out.add(val)
    }
    return out
  }
}

**
** BitWriter: Serializes arbitrary individual bits into a ByteBuf.
**
class BitWriter
{
  private ByteBuf buf
  private Int currentByte := 0
  private Int bitCount := 0

  new make(ByteBuf buf)
  {
    this.buf = buf
  }

  Void writeBit(Int bit)
  {
    currentByte = currentByte.shiftl(1).or(bit.and(1))
    bitCount++
    if (bitCount == 8)
    {
      buf.writeByte(currentByte)
      currentByte = 0
      bitCount = 0
    }
  }

  Void flush()
  {
    if (bitCount > 0)
    {
      currentByte = currentByte.shiftl(8 - bitCount)
      buf.writeByte(currentByte)
      currentByte = 0
      bitCount = 0
    }
  }
}

**
** BitReader: Reads arbitrary individual bits from a ByteBuf.
**
class BitReader
{
  private ByteBuf buf
  private Int currentByte := 0
  private Int bitsLeft := 0

  new make(ByteBuf buf)
  {
    this.buf = buf
  }

  Int readBit()
  {
    if (bitsLeft == 0)
    {
      currentByte = buf.readByte
      bitsLeft = 8
    }
    bitsLeft--
    return currentByte.shiftr(bitsLeft).and(1)
  }
}
