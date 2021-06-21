**
** High-performance streaming state-machine parser for RESP2 and RESP3 protocols.
** Supports non-blocking incremental parsing across fragmented network packets,
** nested arrays, and inline telnet commands.
**
class RespParser
{
  **
  ** Parse the next complete RESP value from the buffer.
  ** Returns null if the buffer contains only a partial message,
  ** leaving the reader index unchanged so additional bytes can be appended.
  **
  static RespValue? parse(ByteBuf buf)
  {
    if (buf.readableBytes == 0) return null

    startIdx := buf.readerIndex
    prefix := buf.readByte

    switch (prefix)
    {
      case '+': // Simple String
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.simpleString(line)

      case '-': // Error
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.error(line)

      case ':': // Integer
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.integer(line.toInt)

      case '$': // Bulk String
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        len := line.toInt
        if (len == -1) return RespValue.nil

        // Need len bytes + 2 bytes for CRLF
        if (buf.readableBytes < len + 2)
        {
          buf.setReaderIndex(startIdx)
          return null
        }

        rawBytes := buf.readBytes(len)
        cr := buf.readByte
        lf := buf.readByte
        if (cr != '\r' || lf != '\n')
        {
          buf.setReaderIndex(startIdx)
          throw IOErr("Expected CRLF after bulk string payload, got: $cr, $lf")
        }

        strBuf := Buf(len)
        for (i := 0; i < rawBytes.size; ++i)
          strBuf.write(rawBytes[i])
        return RespValue.bulkString(strBuf.flip.readAllStr(false))

      case '*': // Array
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        count := line.toInt
        if (count == -1) return RespValue.nil

        RespValue[] items := RespValue[,]
        for (i := 0; i < count; ++i)
        {
          item := parse(buf)
          if (item == null)
          {
            buf.setReaderIndex(startIdx)
            return null
          }
          items.add(item)
        }
        return RespValue.array(items)

      case '#': // Boolean (RESP3)
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.boolean(line == "t")

      case ',': // Double (RESP3)
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.double(line.toFloat)

      case '_': // Null (RESP3)
        line := readLine(buf)
        if (line == null) { buf.setReaderIndex(startIdx); return null }
        return RespValue.nil

      default:
        // Inline command fallback (e.g. "PING\r\n" or "SET k v\r\n")
        buf.setReaderIndex(startIdx)
        line := readLine(buf)
        if (line == null) return null

        parts := line.split(' ')
        RespValue[] items := RespValue[,]
        for (i := 0; i < parts.size; ++i)
        {
          trimmed := parts[i].trim
          if (!trimmed.isEmpty)
            items.add(RespValue.bulkString(trimmed))
        }
        return RespValue.array(items)
    }
  }

  **
  ** Read bytes up to the next CRLF without consuming them if CRLF is absent.
  ** Returns null if a complete line ending with \r\n is not present.
  **
  private static Str? readLine(ByteBuf buf)
  {
    rem := buf.readableBytes
    foundOffset := -1

    // Scan for \r\n
    for (i := 0; i < rem - 1; ++i)
    {
      if (buf.peekByte(i) == '\r' && buf.peekByte(i + 1) == '\n')
      {
        foundOffset = i
        break
      }
    }

    if (foundOffset == -1) return null

    rawBytes := buf.readBytes(foundOffset)

    // Consume \r\n
    buf.readByte
    buf.readByte

    lineBuf := Buf(foundOffset)
    for (i := 0; i < rawBytes.size; ++i)
      lineBuf.write(rawBytes[i])

    return lineBuf.flip.readAllStr(false)
  }
}
