**
** High-speed zero-copy serializer for RESP2 and RESP3 protocol responses.
** Pre-allocates common static responses (OK, PONG, nil, integer 0 and 1)
** to eliminate GC allocation overhead under high throughput.
**
class RespFormatter
{
  static const Str crlf := "\r\n"
  static const Str ok := "+OK\r\n"
  static const Str pong := "+PONG\r\n"
  static const Str nilBulk := "\$-1\r\n"
  static const Str nilArray := "*-1\r\n"
  static const Str zero := ":0\r\n"
  static const Str one := ":1\r\n"

  ** Write a simple string (+<str>\r\n) **
  static Void writeSimpleString(ByteBuf buf, Str str)
  {
    buf.writeByte('+')
    writeAscii(buf, str)
    writeCrlf(buf)
  }

  ** Write an error message (-<msg>\r\n) **
  static Void writeError(ByteBuf buf, Str msg)
  {
    buf.writeByte('-')
    writeAscii(buf, msg)
    writeCrlf(buf)
  }

  ** Write an integer (:<int>\r\n) **
  static Void writeInteger(ByteBuf buf, Int num)
  {
    buf.writeByte(':')
    writeAscii(buf, num.toStr)
    writeCrlf(buf)
  }

  ** Write a bulk string ($<len>\r\n<data>\r\n or $-1\r\n for null) **
  static Void writeBulkString(ByteBuf buf, Str? str)
  {
    if (str == null)
    {
      writeAscii(buf, nilBulk)
      return
    }

    raw := str.toBuf
    buf.writeByte('$')
    writeAscii(buf, raw.size.toStr)
    writeCrlf(buf)
    for (i := 0; i < raw.size; ++i)
      buf.writeByte(raw[i])
    writeCrlf(buf)
  }

  ** Write raw byte array as bulk string **
  static Void writeBulkBytes(ByteBuf buf, Int[]? bytes)
  {
    if (bytes == null)
    {
      writeAscii(buf, nilBulk)
      return
    }

    buf.writeByte('$')
    writeAscii(buf, bytes.size.toStr)
    writeCrlf(buf)
    buf.writeBytes(bytes)
    writeCrlf(buf)
  }

  ** Write an array header (*<count>\r\n or *-1\r\n for null) **
  static Void writeArrayHeader(ByteBuf buf, Int count)
  {
    if (count < 0)
    {
      writeAscii(buf, nilArray)
      return
    }

    buf.writeByte('*')
    writeAscii(buf, count.toStr)
    writeCrlf(buf)
  }

  ** Write a RESP3 boolean (#t\r\n or #f\r\n) **
  static Void writeBoolean(ByteBuf buf, Bool val)
  {
    buf.writeByte('#')
    buf.writeByte(val ? 't' : 'f')
    writeCrlf(buf)
  }

  ** Write a RESP3 double (,num\r\n) **
  static Void writeDouble(ByteBuf buf, Float num)
  {
    buf.writeByte(',')
    writeAscii(buf, num.toStr)
    writeCrlf(buf)
  }

  ** Write a RESP3 null (_\r\n) **
  static Void writeNull(ByteBuf buf)
  {
    buf.writeByte('_')
    writeCrlf(buf)
  }

  ** Serialize a RespValue object recursively into the buffer **
  static Void writeValue(ByteBuf buf, RespValue val)
  {
    switch (val.type)
    {
      case RespType.simpleString:
        writeSimpleString(buf, val.asStr)
      case RespType.error:
        writeError(buf, val.asStr)
      case RespType.integer:
        writeInteger(buf, val.asInt)
      case RespType.bulkString:
        writeBulkString(buf, val.val as Str)
      case RespType.array:
        arr := val.asArray
        writeArrayHeader(buf, arr.size)
        for (i := 0; i < arr.size; ++i)
          writeValue(buf, arr[i])
      case RespType.boolean:
        writeBoolean(buf, val.asBool)
      case RespType.double:
        writeDouble(buf, val.asFloat)
      case RespType.nullValue:
        writeNull(buf)
      default:
        writeBulkString(buf, val.asStr)
    }
  }

  private static Void writeAscii(ByteBuf buf, Str s)
  {
    for (i := 0; i < s.size; ++i)
      buf.writeByte(s[i])
  }

  private static Void writeCrlf(ByteBuf buf)
  {
    buf.writeByte('\r')
    buf.writeByte('\n')
  }
}
