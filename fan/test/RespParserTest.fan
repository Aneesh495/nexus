class RespParserTest : Test
{
  private ByteBuf makeBuf(Str str)
  {
    buf := ByteBuf(str.size)
    raw := str.toBuf
    for (i := 0; i < raw.size; ++i)
      buf.writeByte(raw[i])
    return buf
  }

  Void testSimpleTypes()
  {
    // Simple String
    b1 := makeBuf("+PONG\r\n")
    v1 := RespParser.parse(b1)
    verifyNotNull(v1)
    verifyEq(v1.type, RespType.simpleString)
    verifyEq(v1.asStr, "PONG")

    // Error
    b2 := makeBuf("-ERR syntax error\r\n")
    v2 := RespParser.parse(b2)
    verifyNotNull(v2)
    verifyEq(v2.type, RespType.error)
    verifyEq(v2.asStr, "ERR syntax error")

    // Integer
    b3 := makeBuf(":4294967296\r\n")
    v3 := RespParser.parse(b3)
    verifyNotNull(v3)
    verifyEq(v3.type, RespType.integer)
    verifyEq(v3.asInt, 4294967296)

    // RESP3 Boolean
    b4 := makeBuf("#t\r\n#f\r\n")
    v4a := RespParser.parse(b4)
    verifyNotNull(v4a)
    verifyEq(v4a.type, RespType.boolean)
    verifyEq(v4a.asBool, true)

    v4b := RespParser.parse(b4)
    verifyNotNull(v4b)
    verifyEq(v4b.type, RespType.boolean)
    verifyEq(v4b.asBool, false)

    // RESP3 Double
    b5 := makeBuf(",42.5\r\n")
    v5 := RespParser.parse(b5)
    verifyNotNull(v5)
    verifyEq(v5.type, RespType.double)
    verifyEq(v5.asFloat, 42.5f)

    // RESP3 Null
    b6 := makeBuf("_\r\n")
    v6 := RespParser.parse(b6)
    verifyNotNull(v6)
    verifyEq(v6.type, RespType.nullValue)
    verifyEq(v6.isNull, true)
  }

  Void testBulkStrings()
  {
    // Standard bulk string
    b1 := makeBuf("\$11\r\nhello world\r\n")
    v1 := RespParser.parse(b1)
    verifyNotNull(v1)
    verifyEq(v1.type, RespType.bulkString)
    verifyEq(v1.asStr, "hello world")

    // Empty bulk string
    b2 := makeBuf("\$0\r\n\r\n")
    v2 := RespParser.parse(b2)
    verifyNotNull(v2)
    verifyEq(v2.type, RespType.bulkString)
    verifyEq(v2.asStr, "")

    // Null bulk string
    b3 := makeBuf("\$-1\r\n")
    v3 := RespParser.parse(b3)
    verifyNotNull(v3)
    verifyEq(v3.isNull, true)
  }

  Void testArrays()
  {
    // Array: ["PING"]
    b1 := makeBuf("*1\r\n\$4\r\nPING\r\n")
    v1 := RespParser.parse(b1)
    verifyNotNull(v1)
    verifyEq(v1.type, RespType.array)
    verifyEq(v1.asArray.size, 1)
    verifyEq(v1.asArray[0].asStr, "PING")

    // Array: ["SET", "key1", "value1"]
    b2 := makeBuf("*3\r\n\$3\r\nSET\r\n\$4\r\nkey1\r\n\$6\r\nvalue1\r\n")
    v2 := RespParser.parse(b2)
    verifyNotNull(v2)
    arr := v2.asArray
    verifyEq(arr.size, 3)
    verifyEq(arr[0].asStr, "SET")
    verifyEq(arr[1].asStr, "key1")
    verifyEq(arr[2].asStr, "value1")

    // Empty array
    b3 := makeBuf("*0\r\n")
    v3 := RespParser.parse(b3)
    verifyNotNull(v3)
    verifyEq(v3.type, RespType.array)
    verifyEq(v3.asArray.size, 0)

    // Null array
    b4 := makeBuf("*-1\r\n")
    v4 := RespParser.parse(b4)
    verifyNotNull(v4)
    verifyEq(v4.isNull, true)
  }

  Void testPartialStreaming()
  {
    // Feed bytes in small increments
    full := "*2\r\n\$3\r\nGET\r\n\$8\r\nusername\r\n"
    buf := ByteBuf(full.size)

    raw := full.toBuf
    // Feed first 10 bytes: "*2\r\n$3\r\nGE" (incomplete bulk string)
    for (i := 0; i < 10; ++i)
      buf.writeByte(raw[i])

    verifyNull(RespParser.parse(buf))
    verifyEq(buf.readerIndex, 0) // Did not consume partial frame

    // Feed up to 18 bytes
    for (i := 10; i < 18; ++i)
      buf.writeByte(raw[i])

    verifyNull(RespParser.parse(buf))
    verifyEq(buf.readerIndex, 0)

    // Feed remaining bytes
    for (i := 18; i < raw.size; ++i)
      buf.writeByte(raw[i])

    v := RespParser.parse(buf)
    verifyNotNull(v)
    verifyEq(v.type, RespType.array)
    verifyEq(v.asArray.size, 2)
    verifyEq(v.asArray[0].asStr, "GET")
    verifyEq(v.asArray[1].asStr, "username")
    verifyEq(buf.readableBytes, 0)
  }

  Void testInlineTelnetCommand()
  {
    b1 := makeBuf("PING\r\n")
    v1 := RespParser.parse(b1)
    verifyNotNull(v1)
    verifyEq(v1.type, RespType.array)
    verifyEq(v1.asArray.size, 1)
    verifyEq(v1.asArray[0].asStr, "PING")

    b2 := makeBuf("SET mykey myval\r\n")
    v2 := RespParser.parse(b2)
    verifyNotNull(v2)
    verifyEq(v2.type, RespType.array)
    verifyEq(v2.asArray.size, 3)
    verifyEq(v2.asArray[0].asStr, "SET")
    verifyEq(v2.asArray[1].asStr, "mykey")
    verifyEq(v2.asArray[2].asStr, "myval")
  }
}
