class CliBenchmarkTest : Test
{
  Void testCliFormatting()
  {
    verifyEq(NexusCli.formatResponse(RespValue.simpleString("PONG")), "PONG")
    verifyEq(NexusCli.formatResponse(RespValue.error("ERR bad command")), "(error) ERR bad command")
    verifyEq(NexusCli.formatResponse(RespValue.integer(42)), "(integer) 42")
    verifyEq(NexusCli.formatResponse(RespValue.bulkString("alpha")), "\"alpha\"")
    verifyEq(NexusCli.formatResponse(RespValue.nil), "(nil)")
    verifyEq(NexusCli.formatResponse(RespValue.boolean(true)), "true")

    arr := RespValue.array([RespValue.bulkString("k1"), RespValue.bulkString("v1")])
    formattedArr := NexusCli.formatResponse(arr)
    verifyTrue(formattedArr.contains("1) \"k1\""))
    verifyTrue(formattedArr.contains("2) \"v1\""))
  }

  Void testBenchmarkExecution()
  {
    res := NexusBenchmark.runBenchmark(500)

    verifyTrue(res["opsPerSec"] > 0.0f)
    verifyTrue(res["p50Millis"] >= 0.0f)
    verifyTrue(res["p95Millis"] >= res["p50Millis"])
    verifyTrue(res["p99Millis"] >= res["p95Millis"])
    verifyTrue(res["totalSec"] > 0.0f)
  }
}
