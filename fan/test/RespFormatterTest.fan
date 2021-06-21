class RespFormatterTest : Test
{
  Void testStaticFastPaths()
  {
    verifyEq(RespFormatter.ok, "+OK\r\n")
    verifyEq(RespFormatter.pong, "+PONG\r\n")
    verifyEq(RespFormatter.nilBulk, "\$-1\r\n")
    verifyEq(RespFormatter.nilArray, "*-1\r\n")
    verifyEq(RespFormatter.zero, ":0\r\n")
    verifyEq(RespFormatter.one, ":1\r\n")
  }

  Void testPrimitiveFormatting()
  {
    buf := ByteBuf(128)

    // Simple String
    RespFormatter.writeSimpleString(buf, "QUEUED")
    verifyEq(buf.readUtf8Bytes, "+QUEUED\r\n")

    // Error
    buf.clear
    RespFormatter.writeError(buf, "WRONGTYPE Operation against key holding wrong kind of value")
    verifyEq(buf.readUtf8Bytes, "-WRONGTYPE Operation against key holding wrong kind of value\r\n")

    // Integer
    buf.clear
    RespFormatter.writeInteger(buf, 123456789)
    verifyEq(buf.readUtf8Bytes, ":123456789\r\n")

    // Boolean
    buf.clear
    RespFormatter.writeBoolean(buf, true)
    verifyEq(buf.readUtf8Bytes, "#t\r\n")

    // Double
    buf.clear
    RespFormatter.writeDouble(buf, 3.1415f)
    verifyEq(buf.readUtf8Bytes, ",3.1415\r\n")

    // Null
    buf.clear
    RespFormatter.writeNull(buf)
    verifyEq(buf.readUtf8Bytes, "_\r\n")
  }

  Void testBulkStrings()
  {
    buf := ByteBuf(128)

    // Standard string
    RespFormatter.writeBulkString(buf, "cluster_state_ok")
    verifyEq(buf.readUtf8Bytes, "\$16\r\ncluster_state_ok\r\n")

    // Empty string
    buf.clear
    RespFormatter.writeBulkString(buf, "")
    verifyEq(buf.readUtf8Bytes, "\$0\r\n\r\n")

    // Null string
    buf.clear
    RespFormatter.writeBulkString(buf, null)
    verifyEq(buf.readUtf8Bytes, "\$-1\r\n")

    // Bulk bytes
    buf.clear
    RespFormatter.writeBulkBytes(buf, [0x41, 0x42, 0x43])
    verifyEq(buf.readUtf8Bytes, "\$3\r\nABC\r\n")
  }

  Void testArraysAndNestedValues()
  {
    buf := ByteBuf(128)

    // Array of 2 bulk strings
    RespFormatter.writeArrayHeader(buf, 2)
    RespFormatter.writeBulkString(buf, "GET")
    RespFormatter.writeBulkString(buf, "account:101")
    verifyEq(buf.readUtf8Bytes, "*2\r\n\$3\r\nGET\r\n\$11\r\naccount:101\r\n")

    // Null array
    buf.clear
    RespFormatter.writeArrayHeader(buf, -1)
    verifyEq(buf.readUtf8Bytes, "*-1\r\n")
  }

  Void testRoundtripWithParser()
  {
    original := RespValue.array([
      RespValue.simpleString("TRANSACTION_OK"),
      RespValue.integer(42),
      RespValue.bulkString("snapshot_v2"),
      RespValue.nil,
      RespValue.boolean(true)
    ])

    buf := ByteBuf(256)
    RespFormatter.writeValue(buf, original)

    parsed := RespParser.parse(buf)
    verifyNotNull(parsed)
    verifyEq(parsed.type, RespType.array)

    arr := parsed.asArray
    verifyEq(arr.size, 5)
    verifyEq(arr[0].type, RespType.simpleString)
    verifyEq(arr[0].asStr, "TRANSACTION_OK")
    verifyEq(arr[1].type, RespType.integer)
    verifyEq(arr[1].asInt, 42)
    verifyEq(arr[2].type, RespType.bulkString)
    verifyEq(arr[2].asStr, "snapshot_v2")
    verifyEq(arr[3].isNull, true)
    verifyEq(arr[4].type, RespType.boolean)
    verifyEq(arr[4].asBool, true)
  }
}
