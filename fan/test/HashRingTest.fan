**
** Unit tests for HashRing consistent hashing and replica routing.
**
class HashRingTest : Test
{
  Void testSingleNode()
  {
    ring := HashRing(64)
    verifyEq(ring.nodeCount, 0)
    verifyEq(ring.locatePrimary("testKey"), null)

    n1 := NodeId("node-1")
    ring.addNode(n1)

    verifyEq(ring.nodeCount, 1)
    verifyEq(ring.vnodeCount, 64)

    verifyEq(ring.locatePrimary("keyA"), n1)
    verifyEq(ring.locatePrimary("keyB"), n1)

    replicas := ring.locateReplicas("keyA", 3)
    verifyEq(replicas.size, 1)
    verifyEq(replicas[0], n1)
  }

  Void testDistributionAndReplicas()
  {
    ring := HashRing(128)
    n1 := NodeId("node-1")
    n2 := NodeId("node-2")
    n3 := NodeId("node-3")

    ring.addNode(n1)
    ring.addNode(n2)
    ring.addNode(n3)

    verifyEq(ring.nodeCount, 3)
    verifyEq(ring.vnodeCount, 3 * 128)

    counts := Str:Int["node-1": 0, "node-2": 0, "node-3": 0]
    totalKeys := 1000

    for (i := 0; i < totalKeys; ++i)
    {
      primary := ring.locatePrimary("distributed-key-$i")
      verify(primary != null)
      counts[primary.id] = counts[primary.id] + 1

      // 2 replicas must return 2 distinct physical nodes
      reps := ring.locateReplicas("distributed-key-$i", 2)
      verifyEq(reps.size, 2)
      verify(reps[0] != reps[1])
    }

    // Each node should receive roughly 33% of the keys (25% to 42% tolerance)
    counts.each |c, id|
    {
      share := c.toFloat / totalKeys.toFloat
      verify(share >= 0.20f)
      verify(share <= 0.45f)
    }
  }

  Void testMinimalMovementOnNodeAddition()
  {
    ring := HashRing(128)
    ring.addNode(NodeId("node-A"))
    ring.addNode(NodeId("node-B"))

    initialLocations := Str:Str[:]
    for (i := 0; i < 500; ++i)
    {
      k := "item-$i"
      initialLocations[k] = ring.locatePrimary(k).id
    }

    // Add node-C
    ring.addNode(NodeId("node-C"))

    movedKeys := 0
    for (i := 0; i < 500; ++i)
    {
      k := "item-$i"
      newLoc := ring.locatePrimary(k).id
      if (newLoc != initialLocations[k])
      {
        movedKeys++
        // Keys that moved must have moved to the new node-C
        verifyEq(newLoc, "node-C")
      }
    }

    // In consistent hashing, adding 1 node to 2 nodes should move approximately 1/3 of the keys (20% to 45%)
    movedRatio := movedKeys.toFloat / 500.0f
    verify(movedRatio >= 0.15f)
    verify(movedRatio <= 0.50f)
  }
}
