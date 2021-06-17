**
** High-speed binary protocol codec for typed request and response messages.
** Encodes structured payloads into ByteBuf payloads wrapped in BinaryFrames.
**
class BinaryCodec
{
  static const Int typePing  := 1
  static const Int typePong  := 2
  static const Int typeGet   := 3
  static const Int typePut   := 4
  static const Int typeDel   := 5
  static const Int typeError := 99

  ** Encode a PING request **
  static BinaryFrame encodePing(Int correlationId)
  {
    return BinaryFrame(typePing, correlationId, Int[,])
  }

  ** Encode a PONG heartbeat response **
  static BinaryFrame encodePong(Int correlationId, Int uptimeMillis)
  {
    buf := ByteBuf(8)
    buf.writeI8(uptimeMillis)
    return BinaryFrame(typePong, correlationId, buf.readBytes(8), BinaryFrame.flagResponse)
  }

  ** Encode a GET request for a key **
  static BinaryFrame encodeGet(Int correlationId, Str key)
  {
    buf := ByteBuf(key.size + 4)
    buf.writeUtf8(key)
    return BinaryFrame(typeGet, correlationId, buf.readBytes(buf.writerIndex))
  }

  ** Encode a GET response **
  static BinaryFrame encodeGetResponse(Int correlationId, Bool found, Str? val)
  {
    buf := ByteBuf(val == null ? 1 : val.size + 5)
    buf.writeByte(found ? 1 : 0)
    if (found && val != null)
      buf.writeUtf8(val)
    return BinaryFrame(typeGet, correlationId, buf.readBytes(buf.writerIndex), BinaryFrame.flagResponse)
  }

  ** Encode a PUT request for a key-value entry with optional TTL **
  static BinaryFrame encodePut(Int correlationId, Str key, Str val, Int ttlMillis := 0)
  {
    buf := ByteBuf(key.size + val.size + 16)
    buf.writeUtf8(key)
    buf.writeUtf8(val)
    buf.writeI8(ttlMillis)
    return BinaryFrame(typePut, correlationId, buf.readBytes(buf.writerIndex))
  }

  ** Encode a PUT response acknowledging storage **
  static BinaryFrame encodePutResponse(Int correlationId, Bool success)
  {
    buf := ByteBuf(1)
    buf.writeByte(success ? 1 : 0)
    return BinaryFrame(typePut, correlationId, buf.readBytes(1), BinaryFrame.flagResponse)
  }

  ** Encode a DEL request for a key **
  static BinaryFrame encodeDel(Int correlationId, Str key)
  {
    buf := ByteBuf(key.size + 4)
    buf.writeUtf8(key)
    return BinaryFrame(typeDel, correlationId, buf.readBytes(buf.writerIndex))
  }

  ** Encode a DEL response indicating whether entry existed **
  static BinaryFrame encodeDelResponse(Int correlationId, Bool existed)
  {
    buf := ByteBuf(1)
    buf.writeByte(existed ? 1 : 0)
    return BinaryFrame(typeDel, correlationId, buf.readBytes(1), BinaryFrame.flagResponse)
  }

  ** Encode an ERROR response with diagnostic message **
  static BinaryFrame encodeError(Int correlationId, Str message)
  {
    buf := ByteBuf(message.size + 4)
    buf.writeUtf8(message)
    return BinaryFrame(typeError, correlationId, buf.readBytes(buf.writerIndex), BinaryFrame.flagResponse)
  }

  ** Decode a GET key from request frame payload **
  static Str decodeGet(BinaryFrame frame)
  {
    buf := ByteBuf(frame.payload.size)
    buf.writeBytes(frame.payload)
    return buf.readUtf8
  }

  ** Decode PUT key, val, and ttlMillis from request frame payload **
  static Str[] decodePut(BinaryFrame frame)
  {
    buf := ByteBuf(frame.payload.size)
    buf.writeBytes(frame.payload)
    key := buf.readUtf8
    val := buf.readUtf8
    ttl := buf.readI8
    return [key, val, ttl.toStr]
  }

  ** Decode DEL key from request frame payload **
  static Str decodeDel(BinaryFrame frame)
  {
    buf := ByteBuf(frame.payload.size)
    buf.writeBytes(frame.payload)
    return buf.readUtf8
  }

  ** Decode error message from error response frame **
  static Str decodeError(BinaryFrame frame)
  {
    buf := ByteBuf(frame.payload.size)
    buf.writeBytes(frame.payload)
    return buf.readUtf8
  }
}
