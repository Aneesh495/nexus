class RespCommandDispatcherTest : Test
{
  private RespValue cmd(Str[] tokens)
  {
    RespValue[] items := RespValue[,]
    for (i := 0; i < tokens.size; ++i)
      items.add(RespValue.bulkString(tokens[i]))
    return RespValue.array(items)
  }

  Void testPingEchoInfo()
  {
    d := RespCommandDispatcher()

    r1 := d.dispatch(cmd(["PING"]))
    verifyEq(r1.asStr, "PONG")

    r2 := d.dispatch(cmd(["PING", "hello cluster"]))
    verifyEq(r2.asStr, "hello cluster")

    r3 := d.dispatch(cmd(["ECHO", "test payload"]))
    verifyEq(r3.asStr, "test payload")

    r4 := d.dispatch(cmd(["DBSIZE"]))
    verifyEq(r4.asInt, 0)

    r5 := d.dispatch(cmd(["INFO"]))
    verifyTrue(r5.asStr.contains("nexus_version:2.0.0"))
  }

  Void testStringOperations()
  {
    d := RespCommandDispatcher()

    // SET and GET
    verifyEq(d.dispatch(cmd(["SET", "greeting", "hello"])).asStr, "OK")
    verifyEq(d.dispatch(cmd(["GET", "greeting"])).asStr, "hello")
    verifyTrue(d.dispatch(cmd(["GET", "nonexistent"])).isNull)

    // SETNX
    verifyEq(d.dispatch(cmd(["SETNX", "greeting", "world"])).asInt, 0)
    verifyEq(d.dispatch(cmd(["SETNX", "new_key", "val"])).asInt, 1)

    // MSET and MGET
    verifyEq(d.dispatch(cmd(["MSET", "k1", "v1", "k2", "v2"])).asStr, "OK")
    mgetRes := d.dispatch(cmd(["MGET", "k1", "k2", "missing"])).asArray
    verifyEq(mgetRes.size, 3)
    verifyEq(mgetRes[0].asStr, "v1")
    verifyEq(mgetRes[1].asStr, "v2")
    verifyTrue(mgetRes[2].isNull)

    // EXISTS and DEL
    verifyEq(d.dispatch(cmd(["EXISTS", "k1", "k2", "missing"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["DEL", "k1", "k2"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["EXISTS", "k1"])).asInt, 0)

    // SET with EX and TTL
    d.dispatch(cmd(["SET", "temp", "val", "EX", "10"]))
    ttl := d.dispatch(cmd(["TTL", "temp"])).asInt
    verifyTrue(ttl > 0 && ttl <= 10)
  }

  Void testNumericIncrements()
  {
    d := RespCommandDispatcher()

    verifyEq(d.dispatch(cmd(["INCR", "counter"])).asInt, 1)
    verifyEq(d.dispatch(cmd(["INCR", "counter"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["INCRBY", "counter", "10"])).asInt, 12)
    verifyEq(d.dispatch(cmd(["DECR", "counter"])).asInt, 11)
    verifyEq(d.dispatch(cmd(["DECRBY", "counter", "5"])).asInt, 6)

    // Non-integer error
    d.dispatch(cmd(["SET", "str_key", "not_a_number"]))
    errRes := d.dispatch(cmd(["INCR", "str_key"]))
    verifyEq(errRes.type, RespType.error)
  }

  Void testHashOperations()
  {
    d := RespCommandDispatcher()

    verifyEq(d.dispatch(cmd(["HSET", "user:1", "name", "Alice"])).asInt, 1)
    verifyEq(d.dispatch(cmd(["HSET", "user:1", "age", "30"])).asInt, 1)
    verifyEq(d.dispatch(cmd(["HSET", "user:1", "name", "Alicia"])).asInt, 0) // Update

    verifyEq(d.dispatch(cmd(["HGET", "user:1", "name"])).asStr, "Alicia")
    verifyEq(d.dispatch(cmd(["HGET", "user:1", "age"])).asStr, "30")
    verifyTrue(d.dispatch(cmd(["HGET", "user:1", "email"])).isNull)
    verifyEq(d.dispatch(cmd(["HLEN", "user:1"])).asInt, 2)

    all := d.dispatch(cmd(["HGETALL", "user:1"])).asArray
    verifyEq(all.size, 4)

    verifyEq(d.dispatch(cmd(["HDEL", "user:1", "age"])).asInt, 1)
    verifyEq(d.dispatch(cmd(["HLEN", "user:1"])).asInt, 1)
  }

  Void testListOperations()
  {
    d := RespCommandDispatcher()

    verifyEq(d.dispatch(cmd(["RPUSH", "queue", "task1", "task2"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["LPUSH", "queue", "task0"])).asInt, 3)
    verifyEq(d.dispatch(cmd(["LLEN", "queue"])).asInt, 3)

    verifyEq(d.dispatch(cmd(["LPOP", "queue"])).asStr, "task0")
    verifyEq(d.dispatch(cmd(["RPOP", "queue"])).asStr, "task2")
    verifyEq(d.dispatch(cmd(["LPOP", "queue"])).asStr, "task1")
    verifyTrue(d.dispatch(cmd(["LPOP", "queue"])).isNull)
  }

  Void testSetOperations()
  {
    d := RespCommandDispatcher()

    verifyEq(d.dispatch(cmd(["SADD", "tags", "systems", "distributed", "systems"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["SCARD", "tags"])).asInt, 2)
    verifyEq(d.dispatch(cmd(["SISMEMBER", "tags", "systems"])).asInt, 1)
    verifyEq(d.dispatch(cmd(["SISMEMBER", "tags", "missing"])).asInt, 0)

    members := d.dispatch(cmd(["SMEMBERS", "tags"])).asArray
    verifyEq(members.size, 2)
  }

  Void testClusterCommands()
  {
    d := RespCommandDispatcher()

    nodes := d.dispatch(cmd(["CLUSTER", "NODES"]))
    verifyTrue(nodes.asStr.contains("myself,master"))

    info := d.dispatch(cmd(["CLUSTER", "INFO"]))
    verifyTrue(info.asStr.contains("cluster_state:ok"))
  }
}
