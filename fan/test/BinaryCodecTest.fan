class BinaryCodecTest : Test
{
  Void testFrameEncodingAndDecoding()
  {
    rawPayload := [0x01, 0x02, 0x03, 0x04, 0x05]
    frame := BinaryFrame(BinaryCodec.typePut, 42, rawPayload, BinaryFrame.flagCompressed)

    verifyEq(frame.msgType, BinaryCodec.typePut)
    verifyEq(frame.correlationId, 42)
    verifyEq(frame.payload, rawPayload)
    verifyEq(frame.isCompressed, true)
    verifyEq(frame.isResponse, false)

    encoded := frame.encode
    verifyEq(encoded.readableBytes, BinaryFrame.headerSize + rawPayload.size)

    decoded := BinaryFrame.decode(encoded)
    verifyNotNull(decoded)
    verifyEq(decoded.msgType, BinaryCodec.typePut)
    verifyEq(decoded.correlationId, 42)
    verifyEq(decoded.payload, rawPayload)
    verifyEq(decoded.flags, BinaryFrame.flagCompressed)
    verifyEq(decoded.checksum, frame.checksum)
  }

  Void testPartialFrameDetection()
  {
    rawPayload := [0x10, 0x20, 0x30, 0x40, 0x50, 0x60]
    frame := BinaryFrame(BinaryCodec.typeGet, 100, rawPayload)
    encoded := frame.encode

    // Create partial buffer with only 20 bytes (header is 24 bytes)
    partialBuf := ByteBuf(20)
    partialBuf.writeBytes(encoded.readBytes(20))

    verifyNull(BinaryFrame.decode(partialBuf))
    verifyEq(partialBuf.readerIndex, 0) // Reader index preserved

    // Now write remaining 4 bytes of header, but none of the payload
    partialBuf.writeBytes(encoded.readBytes(4))
    verifyNull(BinaryFrame.decode(partialBuf))

    // Now complete the frame with payload
    partialBuf.writeBytes(encoded.readBytes(6))
    completeFrame := BinaryFrame.decode(partialBuf)
    verifyNotNull(completeFrame)
    verifyEq(completeFrame.correlationId, 100)
    verifyEq(completeFrame.payload, rawPayload)
  }

  Void testCorruptedCrcDetection()
  {
    rawPayload := [0xAA, 0xBB, 0xCC, 0xDD]
    frame := BinaryFrame(BinaryCodec.typeGet, 77, rawPayload)
    encoded := frame.encode

    // Corrupt one payload byte at the end
    rawBytes := encoded.readBytes(encoded.readableBytes)
    rawBytes[rawBytes.size - 1] = rawBytes[rawBytes.size - 1].xor(0xFF)

    corruptedBuf := ByteBuf(rawBytes.size)
    corruptedBuf.writeBytes(rawBytes)

    verifyErr(IOErr#) |->|
    {
      BinaryFrame.decode(corruptedBuf)
    }
  }

  Void testMagicMismatch()
  {
    badBuf := ByteBuf(32)
    badBuf.writeI4(0xDEADBEEF) // Bad magic
    badBuf.writeByte(1)
    badBuf.writeByte(0)
    badBuf.writeI2(1)
    badBuf.writeI8(1)
    badBuf.writeI4(0)
    badBuf.writeI4(0)

    verifyErr(IOErr#) |->|
    {
      BinaryFrame.decode(badBuf)
    }
  }

  Void testTypedMessagesRoundtrip()
  {
    // PING
    ping := BinaryCodec.encodePing(1)
    verifyEq(ping.msgType, BinaryCodec.typePing)
    verifyEq(ping.payload.size, 0)

    // PONG
    pong := BinaryCodec.encodePong(1, 987654)
    verifyEq(pong.msgType, BinaryCodec.typePong)
    verifyEq(pong.isResponse, true)

    // PUT
    put := BinaryCodec.encodePut(2, "sensor:temperature", "23.85", 60000)
    putParts := BinaryCodec.decodePut(put)
    verifyEq(putParts[0], "sensor:temperature")
    verifyEq(putParts[1], "23.85")
    verifyEq(putParts[2], "60000")

    // PUT response
    putResp := BinaryCodec.encodePutResponse(2, true)
    verifyEq(putResp.isResponse, true)

    // GET
    get := BinaryCodec.encodeGet(3, "sensor:temperature")
    verifyEq(BinaryCodec.decodeGet(get), "sensor:temperature")

    // GET response
    getResp := BinaryCodec.encodeGetResponse(3, true, "23.85")
    verifyEq(getResp.isResponse, true)

    // DEL
    del := BinaryCodec.encodeDel(4, "cache:old_session")
    verifyEq(BinaryCodec.decodeDel(del), "cache:old_session")

    // ERROR
    errFrame := BinaryCodec.encodeError(5, "ClusterTopologyException: Node unreachable")
    verifyEq(BinaryCodec.decodeError(errFrame), "ClusterTopologyException: Node unreachable")
  }
}
