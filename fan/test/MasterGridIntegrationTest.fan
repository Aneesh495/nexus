using concurrent
using inet

class MasterGridIntegrationTest : Test
{
  Void testFullGridReplicationAndPartitioning()
  {
    n1 := NodeId("node-us-east-1", "10.0.1.1", 6379)
    n2 := NodeId("node-us-east-2", "10.0.1.2", 6379)
    n3 := NodeId("node-us-east-3", "10.0.1.3", 6379)

    ring := HashRing(64)
    ring.addNode(n1)
    ring.addNode(n2)
    ring.addNode(n3)

    verifyEq(ring.nodeCount, 3)

    // Store keys in stores dedicated to nodes
    stores := [
      n1.id: PartitionStore(0, 1000, 10 * 1024 * 1024),
      n2.id: PartitionStore(1, 1000, 10 * 1024 * 1024),
      n3.id: PartitionStore(2, 1000, 10 * 1024 * 1024)
    ]

    for (i := 0; i < 60; ++i)
    {
      key := "device:telemetry:${i}"
      val := "sample_data_${i * 10}"

      assignedNode := ring.locatePrimary(key)
      verifyNotNull(assignedNode)

      primaryStore := (PartitionStore)stores[assignedNode.id]
      primaryStore.put(key, val)
    }

    // Verify all keys retrieve correctly from primary
    for (i := 0; i < 60; ++i)
    {
      key := "device:telemetry:${i}"
      expectedVal := "sample_data_${i * 10}"

      assignedNode := ring.locatePrimary(key)
      primaryStore := (PartitionStore)stores[assignedNode.id]
      entry := primaryStore.get(key)
      verifyNotNull(entry)
      verifyEq(entry.val, expectedVal)
    }
  }

  Void testDistributedTransactionAcrossPartitions()
  {
    coordNode := NodeId("coordinator-1", "127.0.0.1", 6379)
    store0 := PartitionStore(0, 1000, 10 * 1024 * 1024)
    store1 := PartitionStore(1, 1000, 10 * 1024 * 1024)

    coord := TwoPhaseCommitCoordinator(coordNode)

    txCtx := coord.beginTransaction
    verifyEq(txCtx.state, TxState.active)

    // Register writes spanning two partitions
    txCtx.bufferWrite("account:alice:balance", "900", 0)
    txCtx.bufferWrite("account:bob:balance", "1100", 1)

    keyToPartition := [
      "account:alice:balance": 0,
      "account:bob:balance": 1
    ]

    storeMap := [
      0: store0,
      1: store1
    ]

    success := coord.commitTransaction(txCtx, storeMap, keyToPartition)
    verifyTrue(success)
    verifyEq(txCtx.state, TxState.committed)

    // Verify written to storage
    verifyEq(store0.get("account:alice:balance")?.val, "900")
    verifyEq(store1.get("account:bob:balance")?.val, "1100")
  }

  Void testClientServerNearCachePipelining()
  {
    server := TcpServer(0)
    server.start
    port := server.localPort

    nearCache := NearCache(500, 60000)
    client := NexusClient("127.0.0.1", port, nearCache)

    try
    {
      client.connect
      verifyTrue(client.isConnected)

      // Bulk write 30 entries
      for (i := 0; i < 30; ++i)
      {
        k := "sensor:${i}"
        v := "temp_${20 + i}"
        client.put(k, v)
      }

      // First read: populates NearCache from network
      for (i := 0; i < 30; ++i)
      {
        k := "sensor:${i}"
        v := client.get(k)
        verifyEq(v, "temp_${20 + i}")
      }
      verifyEq(nearCache.size, 30)
      verifyEq(nearCache.hitCount, 30) // Put inserted into NearCache

      // Second read: served 100% from in-memory NearCache
      for (i := 0; i < 30; ++i)
      {
        k := "sensor:${i}"
        v := client.get(k)
        verifyEq(v, "temp_${20 + i}")
      }
      verifyEq(nearCache.hitCount, 60)

      // Test atomic counter
      verifyEq(client.incr("telemetry:events"), 1)
      verifyEq(client.incr("telemetry:events"), 2)
      verifyEq(client.decr("telemetry:events"), 1)
    }
    finally
    {
      client.close
      server.stop
    }
  }
}
