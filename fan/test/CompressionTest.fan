**
** Unit tests for Compression (RLE and LZ dictionary).
**
class CompressionTest : Test
{
  Void testRleRuns()
  {
    buf := ByteBuf()
    // 50 'A's, then 30 'B's, then literals 'XYZ'
    for (i := 0; i < 50; ++i) buf.writeByte('A')
    for (i := 0; i < 30; ++i) buf.writeByte('B')
    buf.writeByte('X'); buf.writeByte('Y'); buf.writeByte('Z')

    origSize := buf.readableBytes
    compressed := Compression.compressRle(buf)

    // Compression ratio should be high for runs
    verify(compressed.readableBytes < origSize)

    decompressed := Compression.decompressRle(compressed)
    verifyEq(decompressed.readableBytes, origSize)

    for (i := 0; i < 50; ++i) verifyEq(decompressed.readByte, 'A')
    for (i := 0; i < 30; ++i) verifyEq(decompressed.readByte, 'B')
    verifyEq(decompressed.readByte, 'X')
    verifyEq(decompressed.readByte, 'Y')
    verifyEq(decompressed.readByte, 'Z')
  }

  Void testLzDictionaryCompression()
  {
    buf := ByteBuf()
    pattern := "NEXUS_DISTRIBUTED_IN_MEMORY_DATA_GRID_"
    // Repeat pattern 10 times
    for (i := 0; i < 10; ++i)
    {
      buf.writeUtf8(pattern)
    }

    origSize := buf.readableBytes
    compressed := Compression.compressLz(buf)
    verify(compressed.readableBytes < origSize)

    decompressed := Compression.decompressLz(compressed)
    verifyEq(decompressed.readableBytes, origSize)

    for (i := 0; i < 10; ++i)
    {
      str := decompressed.readUtf8
      verifyEq(str, pattern)
    }
  }

  Void testEmptyBuffer()
  {
    buf := ByteBuf()
    comp := Compression.compressLz(buf)
    decomp := Compression.decompressLz(comp)
    verifyEq(decomp.readableBytes, 0)
  }
}
