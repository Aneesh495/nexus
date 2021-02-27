**
** Unit tests for Bits manipulation and universal coding.
**
class BitsTest : Test
{
  Void testPopCount()
  {
    verifyEq(Bits.popCount(0), 0)
    verifyEq(Bits.popCount(1), 1)
    verifyEq(Bits.popCount(3), 2)
    verifyEq(Bits.popCount(0xFF), 8)
    verifyEq(Bits.popCount(0x5555555555555555), 32)
    verifyEq(Bits.popCount(0xAAAAAAAAAAAAAAAA), 32)
    verifyEq(Bits.popCount(-1), 64)
  }

  Void testLeadingAndTrailingZeros()
  {
    verifyEq(Bits.numberOfLeadingZeros(0), 64)
    verifyEq(Bits.numberOfLeadingZeros(1), 63)
    verifyEq(Bits.numberOfLeadingZeros(2), 62)
    verifyEq(Bits.numberOfLeadingZeros(0x8000000000000000), 0)

    verifyEq(Bits.numberOfTrailingZeros(0), 64)
    verifyEq(Bits.numberOfTrailingZeros(1), 0)
    verifyEq(Bits.numberOfTrailingZeros(2), 1)
    verifyEq(Bits.numberOfTrailingZeros(4), 2)
    verifyEq(Bits.numberOfTrailingZeros(8), 3)
    verifyEq(Bits.numberOfTrailingZeros(16), 4)
  }

  Void testPowerOfTwo()
  {
    verifyEq(Bits.isPowerOfTwo(0), false)
    verifyEq(Bits.isPowerOfTwo(1), true)
    verifyEq(Bits.isPowerOfTwo(2), true)
    verifyEq(Bits.isPowerOfTwo(3), false)
    verifyEq(Bits.isPowerOfTwo(4), true)
    verifyEq(Bits.isPowerOfTwo(1024), true)
    verifyEq(Bits.isPowerOfTwo(1023), false)

    verifyEq(Bits.nextPowerOfTwo(0), 1)
    verifyEq(Bits.nextPowerOfTwo(1), 1)
    verifyEq(Bits.nextPowerOfTwo(2), 2)
    verifyEq(Bits.nextPowerOfTwo(3), 4)
    verifyEq(Bits.nextPowerOfTwo(5), 8)
    verifyEq(Bits.nextPowerOfTwo(1000), 1024)
  }

  Void testEliasGammaCoding()
  {
    raw := [1, 2, 3, 4, 5, 10, 25, 64, 127, 256, 1000, 65535]
    buf := ByteBuf()
    writer := BitWriter(buf)
    Bits.encodeEliasGamma(raw, writer)
    writer.flush

    reader := BitReader(buf)
    decoded := Bits.decodeEliasGamma(reader, raw.size)

    verifyEq(decoded.size, raw.size)
    for (i := 0; i < raw.size; ++i)
    {
      verifyEq(decoded[i], raw[i])
    }
  }
}
