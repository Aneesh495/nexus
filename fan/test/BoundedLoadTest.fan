**
** Unit tests for BoundedLoadConsistentHash.
**
class BoundedLoadTest : Test
{
  Void testBoundedLoadEnforcement()
  {
    ring := HashRing(64)
    n1 := NodeId("server-1")
    n2 := NodeId("server-2")
    n3 := NodeId("server-3")

    ring.addNode(n1)
    ring.addNode(n2)
    ring.addNode(n3)

    // epsilon = 0.20 (max 120% of average load)
    bl := BoundedLoadConsistentHash(ring, 0.20f)

    totalKeys := 600
    for (i := 0; i < totalKeys; ++i)
    {
      assigned := bl.assignKey("workload-key-$i")
      verify(assigned != null)
    }

    avgLoad := totalKeys / 3 // 200
    maxAllowed := (200.0f * 1.20f).ceil.toInt + 2 // ~242

    l1 := bl.getLoad(n1)
    l2 := bl.getLoad(n2)
    l3 := bl.getLoad(n3)

    verifyEq(l1 + l2 + l3, totalKeys)
    verify(l1 <= maxAllowed)
    verify(l2 <= maxAllowed)
    verify(l3 <= maxAllowed)
  }

  Void testReleaseKey()
  {
    ring := HashRing(32)
    node := NodeId("node-solo")
    ring.addNode(node)

    bl := BoundedLoadConsistentHash(ring, 0.25f)
    bl.assignKey("k1")
    bl.assignKey("k2")
    verifyEq(bl.getLoad(node), 2)

    bl.releaseKey(node)
    verifyEq(bl.getLoad(node), 1)

    bl.releaseKey(node)
    verifyEq(bl.getLoad(node), 0)
  }
}
