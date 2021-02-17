**
** Unit tests for ByteBuf operations and binary codecs.
**
class ByteBufTest : Test
{
  Void testPrimitivesBigEndian()
  {
    buf := ByteBuf(32, true)
    buf.writeByte(0x42)
    buf.writeI2(0x1234)
    buf.writeI4(0x12345678)
    buf.writeI8(0x0102030405060708)

    verifyEq(buf.readableBytes, 1 + 2 + 4 + 8)
    verifyEq(buf.readByte, 0x42)
    verifyEq(buf.readI2, 0x1234)
    verifyEq(buf.readI4, 0x12345678)
    verifyEq(buf.readI8, 0x0102030405060708)
    verifyEq(buf.readableBytes, 0)
  }

  Void testPrimitivesLittleEndian()
  {
    buf := ByteBuf(32, false)
    buf.writeI2(0x1234)
    buf.writeI4(0x12345678)

    verifyEq(buf.readI2, 0x1234)
    verifyEq(buf.readI4, 0x12345678)
  }

  Void testVarIntAndZigZag()
  {
    buf := ByteBuf()
    numbers := [0, 1, 127, 128, 300, 16384, 2097152, 9876543210]
    numbers.each |n| { buf.writeVarInt(n) }
    numbers.each |n| { verifyEq(buf.readVarInt, n) }

    signed := [0, -1, 1, -64, 64, -128, 128, -2147483648, 2147483647]
    signed.each |s| { buf.writeZigZag(s) }
    signed.each |s| { verifyEq(buf.readZigZag, s) }
  }

  Void testUtf8Serialization()
  {
    buf := ByteBuf()
    buf.writeUtf8("Hello, Nexus Data Grid!")
    buf.writeUtf8("Distributed actor state")

    verifyEq(buf.readUtf8, "Hello, Nexus Data Grid!")
    verifyEq(buf.readUtf8, "Distributed actor state")
  }

  Void testFloats()
  {
    buf := ByteBuf()
    buf.writeF8(3.141592653589793f)
    buf.writeF8(-42.001f)

    verify((buf.readF8 - 3.141592653589793f).abs < 0.0000000001f)
    verify((buf.readF8 - -42.001f).abs < 0.0000000001f)
  }

  Void testSliceAndCompact()
  {
    buf := ByteBuf()
    buf.writeI4(100)
    buf.writeI4(200)
    buf.writeI4(300)

    slice := buf.slice(8)
    verifyEq(slice.readableBytes, 8)
    verifyEq(slice.readI4, 100)
    verifyEq(slice.readI4, 200)

    verifyEq(buf.readableBytes, 4)
    verifyEq(buf.readI4, 300)

    buf.compact
    verifyEq(buf.readableBytes, 0)
    verifyEq(buf.readerIndex, 0)
  }

  Void testCrc32c()
  {
    buf := ByteBuf()
    buf.writeBytes([0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39])
    // Standard CRC32C for "123456789" is 0xE3069283
    crc := buf.crc32c
    verifyEq(crc, 0xE3069283)
  }

  Void testUnderflow()
  {
    buf := ByteBuf()
    buf.writeByte(1)
    verifyEq(buf.readByte, 1)
    verifyErr(IOErr#) { buf.readByte }
  }
}
