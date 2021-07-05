class NexusClientTest : Test
{
  Void testNearCacheHitsAndMisses()
  {
    nc := NearCache(100, 60000)
    verifyEq(nc.size, 0)
    verifyEq(nc.hitCount, 0)
    verifyEq(nc.missCount, 0)

    // Miss on missing key
    verifyNull(nc.get("user:1"))
    verifyEq(nc.missCount, 1)

    // Put and hit
    nc.put("user:1", "Bob")
    verifyEq(nc.size, 1)
    verifyEq(nc.get("user:1"), "Bob")
    verifyEq(nc.hitCount, 1)
    verifyEq(nc.hitRatio, 0.5f)
  }

  Void testNearCacheLruEviction()
  {
    nc := NearCache(3, 60000)

    nc.put("k1", "v1")
    nc.put("k2", "v2")
    nc.put("k3", "v3")
    verifyEq(nc.size, 3)

    // Touch k1 to make k2 the least recently used
    nc.get("k1")

    // Insert 4th item: should evict k2
    nc.put("k4", "v4")
    verifyEq(nc.size, 3)

    verifyNotNull(nc.get("k1"))
    verifyNull(nc.get("k2")) // Evicted
    verifyNotNull(nc.get("k3"))
    verifyNotNull(nc.get("k4"))
  }

  Void testNearCacheExpiryAndInvalidation()
  {
    nc := NearCache(10, 100) // 100ms TTL

    now := 1000000
    nc.put("session:1", "active", now)
    verifyEq(nc.get("session:1", now + 50), "active")

    // Advance beyond 100ms
    verifyNull(nc.get("session:1", now + 150))

    // Invalidation
    nc.put("session:2", "active", now)
    verifyNotNull(nc.get("session:2", now))
    nc.invalidate("session:2")
    verifyNull(nc.get("session:2", now))
  }

  Void testClientEndToEndOverTcp()
  {
    server := TcpServer(0)
    server.start
    port := server.localPort

    nearCache := NearCache(100, 60000)
    client := NexusClient("127.0.0.1", port, nearCache)

    try
    {
      // PING
      verifyEq(client.ping, "PONG")
      verifyEq(client.ping("heartbeat"), "heartbeat")

      // PUT and GET
      verifyTrue(client.put("profile:1", "Alice"))
      verifyEq(client.get("profile:1"), "Alice")

      // Second GET must hit near cache
      verifyEq(nearCache.hitCount, 1)
      verifyEq(client.get("profile:1"), "Alice")
      verifyEq(nearCache.hitCount, 2)

      // INCR and DECR
      verifyEq(client.incr("pageviews"), 1)
      verifyEq(client.incr("pageviews"), 2)
      verifyEq(client.decr("pageviews"), 1)

      // EXISTS and REMOVE
      verifyTrue(client.exists("profile:1"))
      verifyTrue(client.remove("profile:1"))
      verifyFalse(client.exists("profile:1"))
      verifyNull(client.get("profile:1"))
    }
    finally
    {
      client.close
      server.stop
    }
  }
}
